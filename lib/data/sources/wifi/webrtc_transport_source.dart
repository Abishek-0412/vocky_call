/// WebRTC transport source — handles signaling and peer connections over WiFi.
///
/// Uses a local TCP signaling server (port 9000) for call control messages
/// and SDP offer/answer + ICE candidate exchange. No STUN/TURN on a LAN.
///
/// Call flow:
///   caller: connectToPeer → CALL_INVITE
///   callee: CALL_ACCEPT, startMedia(isCaller: false)
///   caller: on CALL_ACCEPT → startMedia(isCaller: true) → SDP_OFFER
///   callee: SDP_OFFER → SDP_ANSWER
library webrtc_transport_source;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:vocky_call/core/constants/app_constants.dart';
import 'package:vocky_call/core/errors/exceptions.dart';
import 'package:vocky_call/data/sources/wifi/local_mic_stream.dart';

import 'package:vocky_call/data/sources/i_transport_source.dart';
import 'package:vocky_call/domain/value_objects/transport_type.dart';

abstract interface class IWebRtcTransportSource implements ITransportSource {}

final class WebRtcTransportSource implements IWebRtcTransportSource {
  ServerSocket? _signalingServer;

  // peerId → peer connection (created lazily, shared by concurrent callers)
  final Map<String, Future<RTCPeerConnection>> _peerConnections = {};

  // peerId → signaling socket
  final Map<String, Socket> _signalingClients = {};

  // peerId → ICE candidates received before the remote description was set
  final Map<String, List<RTCIceCandidate>> _pendingCandidates = {};
  final Set<String> _remoteDescriptionSet = {};

  final _audioController = StreamController<Uint8List>.broadcast();
  final _signalingController =
      StreamController<Map<String, dynamic>>.broadcast();

  @override
  TransportType get transportType => TransportType.wifi;

  @override
  Stream<Uint8List> get audioStream => _audioController.stream;

  @override
  Stream<Map<String, dynamic>> get signalingStream =>
      _signalingController.stream;

  // Optional TURN relay, only for testing between emulators, which sit on
  // separate virtual networks. Empty on real devices (LAN host candidates).
  static const _turnUrl = String.fromEnvironment('VOCKY_TURN_URL');
  static const _turnUser = String.fromEnvironment('VOCKY_TURN_USER');
  static const _turnPass = String.fromEnvironment('VOCKY_TURN_PASS');

  static Map<String, dynamic> get _rtcConfig => {
        'iceServers': [
          if (_turnUrl.isNotEmpty)
            {'urls': _turnUrl, 'username': _turnUser, 'credential': _turnPass},
        ],
        if (_turnUrl.isNotEmpty) 'iceTransportPolicy': 'relay',
        'sdpSemantics': 'unified-plan',
      };

  @override
  Future<void> initialize(String localDeviceName) async {
    if (_signalingServer != null) return;
    _signalingServer = await ServerSocket.bind(
      InternetAddress.anyIPv4,
      AppConstants.signalingPort,
      shared: true,
    );
    _signalingServer!.listen(_handleIncomingSocket);
  }

  /// [peerId] is an IP, or "host:port" for a non-default signaling port.
  @override
  Future<void> connectToPeer(String peerId, String localName) async {
    try {
      final (host, port) = _parseHostPort(peerId);
      final socket = await Socket.connect(host, port,
          timeout: const Duration(seconds: 5));
      socket.setOption(SocketOption.tcpNoDelay, true);
      _signalingClients[peerId] = socket;
      _listenOnSocket(socket, () => peerId);
    } catch (e) {
      throw SignalingException('Failed to connect to $peerId: $e');
    }
  }

  @override
  Future<void> startMedia(String peerId, {required bool isCaller}) async {
    final pc = await _ensurePeerConnection(peerId);
    if (!isCaller) return; // callee waits for SDP_OFFER
    final offer = await pc.createOffer({'offerToReceiveAudio': true});
    await pc.setLocalDescription(offer);
    await sendSignal(peerId, {
      'type': AppConstants.sigSdpOffer,
      'sdp': offer.sdp,
    });
  }

  @override
  Future<void> sendSignal(String peerId, Map<String, dynamic> message) async {
    final socket = _signalingClients[peerId];
    if (socket == null) return;
    try {
      socket.write('${jsonEncode(message)}\n');
      await socket.flush();
    } catch (_) {
      // Socket already closed — the onDone handler reports the drop.
    }
  }

  @override
  Future<void> sendAudio(Uint8List chunk) async {
    // WebRTC sends audio through the media track; nothing to do here.
  }

  @override
  Future<void> closeAll() async {
    final pcs = List.of(_peerConnections.values);
    _peerConnections.clear();
    _pendingCandidates.clear();
    _remoteDescriptionSet.clear();
    for (final f in pcs) {
      await _disposePc(f);
    }
    final sockets = List.of(_signalingClients.values);
    _signalingClients.clear(); // clear first so onDone doesn't report a drop
    for (final s in sockets) {
      s.destroy();
    }
  }

  // ── Private Helpers ──────────────────────────────────────────────────────

  (String, int) _parseHostPort(String peerId) {
    final i = peerId.lastIndexOf(':');
    if (i > 0) {
      final port = int.tryParse(peerId.substring(i + 1));
      if (port != null) return (peerId.substring(0, i), port);
    }
    return (peerId, AppConstants.signalingPort);
  }

  Future<RTCPeerConnection> _ensurePeerConnection(String peerId) {
    return _peerConnections[peerId] ??= _createPeerConnection(peerId);
  }

  Future<RTCPeerConnection> _createPeerConnection(String peerId) async {
    final mic = await LocalMicStream.get();
    final pc = await createPeerConnection(_rtcConfig);

    for (final track in mic.getAudioTracks()) {
      await pc.addTrack(track, mic);
    }

    // Remote audio tracks are played by the native WebRTC engine.
    pc.onTrack = (_) {};

    pc.onIceCandidate = (candidate) {
      if (candidate.candidate == null) return;
      sendSignal(peerId, {
        'type': AppConstants.sigIceCandidate,
        'candidate': candidate.toMap(),
      });
    };

    pc.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed &&
          _peerConnections.containsKey(peerId)) {
        _signalingController.add({
          'type': AppConstants.sigCallEnd,
          'fromIp': peerId,
          'reason': 'connection_lost',
        });
      }
    };

    return pc;
  }

  void _handleIncomingSocket(Socket socket) {
    socket.setOption(SocketOption.tcpNoDelay, true);
    // The peer id is fixed by the first message so later messages (which
    // may not carry fromIp) stay on the same key.
    String? peerId;
    _listenOnSocket(socket, () => peerId, onFirst: (msg) {
      peerId = msg['fromIp'] as String? ?? socket.remoteAddress.address;
      _signalingClients[peerId!] = socket;
    });
  }

  void _listenOnSocket(
    Socket socket,
    String? Function() peerId, {
    void Function(Map<String, dynamic>)? onFirst,
  }) {
    var first = true;
    socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
      (line) async {
        if (line.trim().isEmpty) return;
        Map<String, dynamic> msg;
        try {
          msg = jsonDecode(line) as Map<String, dynamic>;
        } catch (_) {
          return; // malformed
        }
        if (first) {
          first = false;
          onFirst?.call(msg);
        }
        final id = peerId();
        if (id != null) await _handleSignalingMessage(msg, id);
      },
      onDone: () => _onSocketClosed(socket, peerId()),
      onError: (_) => _onSocketClosed(socket, peerId()),
      cancelOnError: true,
    );
  }

  void _onSocketClosed(Socket socket, String? peerId) {
    if (peerId == null || _signalingClients[peerId] != socket) return;
    _signalingClients.remove(peerId);
    _signalingController.add({
      'type': AppConstants.sigCallEnd,
      'fromIp': peerId,
      'reason': 'connection_lost',
    });
  }

  Future<void> _handleSignalingMessage(
    Map<String, dynamic> msg,
    String peerId,
  ) async {
    final type = msg['type'] as String?;
    try {
      switch (type) {
        case AppConstants.sigSdpOffer:
          final pc = await _ensurePeerConnection(peerId);
          await pc.setRemoteDescription(
            RTCSessionDescription(msg['sdp'] as String, 'offer'),
          );
          await _flushCandidates(peerId, pc);
          final answer = await pc.createAnswer();
          await pc.setLocalDescription(answer);
          await sendSignal(peerId, {
            'type': AppConstants.sigSdpAnswer,
            'sdp': answer.sdp,
          });

        case AppConstants.sigSdpAnswer:
          final f = _peerConnections[peerId];
          if (f == null) return;
          final pc = await f;
          await pc.setRemoteDescription(
            RTCSessionDescription(msg['sdp'] as String, 'answer'),
          );
          await _flushCandidates(peerId, pc);

        case AppConstants.sigIceCandidate:
          final c = msg['candidate'] as Map<String, dynamic>;
          final candidate = RTCIceCandidate(
            c['candidate'] as String?,
            c['sdpMid'] as String?,
            c['sdpMLineIndex'] as int?,
          );
          final f = _peerConnections[peerId];
          if (f == null || !_remoteDescriptionSet.contains(peerId)) {
            (_pendingCandidates[peerId] ??= []).add(candidate);
            return;
          }
          await (await f).addCandidate(candidate);

        case AppConstants.sigCallDecline:
        case AppConstants.sigCallEnd:
          final f = _peerConnections.remove(peerId);
          _remoteDescriptionSet.remove(peerId);
          _pendingCandidates.remove(peerId);
          _signalingController.add(msg..['fromIp'] = peerId);
          if (f != null) await _disposePc(f);

        default:
          // CALL_INVITE, CALL_ACCEPT → handled by TransportRepositoryImpl.
          _signalingController.add(msg..['fromIp'] = peerId);
      }
    } catch (_) {
      // A failed SDP/ICE step surfaces as a failed connection state.
    }
  }

  /// Close and dispose, so flutter_webrtc frees the connection and resets
  /// its audio state once no connection is left.
  Future<void> _disposePc(Future<RTCPeerConnection> f) async {
    try {
      final pc = await f;
      await pc.close();
      await pc.dispose();
    } catch (_) {}
  }

  Future<void> _flushCandidates(String peerId, RTCPeerConnection pc) async {
    _remoteDescriptionSet.add(peerId);
    final pending = _pendingCandidates.remove(peerId) ?? const [];
    for (final c in pending) {
      await pc.addCandidate(c);
    }
  }

  @override
  void dispose() {
    closeAll();
    _signalingServer?.close();
    _signalingServer = null;
    _audioController.close();
    _signalingController.close();
  }
}
