/// Fake WebRTC transport source for sandbox / testing.
///
/// Simulates the full WebRTC signaling lifecycle using in-process streams.
/// No real TCP sockets, peer connections, or media devices are opened.
/// Implements [IWebRtcTransportSource].
library fake_webrtc_transport_source;

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:vocky_call/core/constants/app_constants.dart';
import 'package:vocky_call/data/sources/wifi/webrtc_transport_source.dart';
import 'package:vocky_call/domain/value_objects/transport_type.dart';

final class FakeWebRtcTransportSource implements IWebRtcTransportSource {
  final _audioController = StreamController<Uint8List>.broadcast();
  final _signalingController =
      StreamController<Map<String, dynamic>>.broadcast();

  Timer? _audioLevelTimer;
  bool _callActive = false;

  // Expose signaling controller so the sandbox control panel can inject events.
  StreamController<Map<String, dynamic>> get signalingInjector =>
      _signalingController;

  @override
  TransportType get transportType => TransportType.wifi;

  @override
  Stream<Uint8List> get audioStream => _audioController.stream;

  @override
  Stream<Map<String, dynamic>> get signalingStream =>
      _signalingController.stream;

  // ── IWebRtcTransportSource implementation ─────────────────────────────────

  @override
  Future<void> initialize(String localDeviceName) async {
    // No-op — sandbox uses in-process streams instead of TCP.
  }

  @override
  Future<void> connectToPeer(String peerIp, String localName) async {
    // Simulate 1.5 s connection delay, then echo back a call-invite
    // as if the remote peer replied with call-accept.
    await Future.delayed(const Duration(milliseconds: 1500));
    _signalingController.add({
      'type': AppConstants.sigCallAccept,
      'from': 'Sandbox Phone A',
      'fromIp': peerIp,
    });
    _startFakeAudioLevel(peerIp);
    _callActive = true;
  }

  @override
  Future<void> sendSignal(
      String peerIp, Map<String, dynamic> message) async {
    // Consume the signal silently — the sandbox reacts to typed triggers
    // via [injectIncomingCall] / [injectCallEnd] instead.
    final type = message['type'];
    if (type == AppConstants.sigCallEnd ||
        type == AppConstants.sigCallDecline) {
      _stopFakeAudioLevel();
      _callActive = false;
    }
  }

  @override
  Future<void> sendAudio(Uint8List chunk) async {
    // No-op — WiFi mode uses WebRTC tracks; audio loop-back not needed.
  }

  @override
  Future<void> startMedia(String peerId, {required bool isCaller}) async {}

  @override
  Future<void> closeAll() async {
    _stopFakeAudioLevel();
    _callActive = false;
  }

  // ── Sandbox helpers (called by SandboxControlPanel) ───────────────────────

  /// Simulate an incoming call from a fake remote peer.
  void injectIncomingCall({
    String callerId = '192.168.1.99',
    String callerName = 'Sandbox Remote',
  }) {
    _signalingController.add({
      'type': AppConstants.sigCallInvite,
      'from': callerName,
      'fromIp': callerId,
      'sessionId': _generateId(),
    });
    _startFakeAudioLevel(callerId);
    _callActive = true;
  }

  /// Simulate the remote peer hanging up mid-call.
  void injectCallEnd({String peerId = '192.168.1.99'}) {
    _signalingController.add({
      'type': AppConstants.sigCallEnd,
      'from': peerId,
      'fromIp': peerId,
      'reason': 'remote_ended',
    });
    _stopFakeAudioLevel();
    _callActive = false;
  }

  bool get isCallActive => _callActive;

  // ── Private ───────────────────────────────────────────────────────────────

  void _startFakeAudioLevel(String peerId) {
    _stopFakeAudioLevel();
    final rng = Random();
    _audioLevelTimer =
        Timer.periodic(const Duration(milliseconds: 400), (_) {
      // Emit a fake audio-level event as a signaling message so the
      // TransportRepositoryImpl converts it to PeerAudioLevelEvent.
      _signalingController.add({
        'type': 'audio_level',
        'peerId': peerId,
        'level': rng.nextDouble(),
      });
    });
  }

  void _stopFakeAudioLevel() {
    _audioLevelTimer?.cancel();
    _audioLevelTimer = null;
  }

  String _generateId() =>
      DateTime.now().millisecondsSinceEpoch.toRadixString(16) +
      Random().nextInt(9999).toString();

  void dispose() {
    closeAll();
    _audioController.close();
    _signalingController.close();
  }
}
