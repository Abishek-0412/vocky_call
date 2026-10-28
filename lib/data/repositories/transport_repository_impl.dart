/// Transport repository implementation.
///
/// Routes calls through appropriate generic transport sources
/// based on the target peer's TransportType. Implements the signaling protocol.
library transport_repository_impl;

import 'dart:async';
import 'dart:typed_data';
import 'dart:math';
import 'package:vocky_call/core/utils/network_utils.dart';
import 'package:vocky_call/core/constants/app_constants.dart';
import 'package:vocky_call/core/errors/failures.dart';
import 'package:vocky_call/core/result/result.dart';
import 'package:vocky_call/core/errors/exceptions.dart';
import 'package:vocky_call/data/sources/i_transport_source.dart';
import 'package:vocky_call/domain/entities/peer_device.dart';
import 'package:vocky_call/domain/entities/call_session.dart';
import 'package:vocky_call/domain/repositories/i_transport_repository.dart';
import 'package:vocky_call/domain/value_objects/transport_type.dart';

final class TransportRepositoryImpl implements ITransportRepository {
  final Map<TransportType, ITransportSource> _sources;
  final String _localDeviceName;

  final _audioController = StreamController<Uint8List>.broadcast();
  final _signalingController = StreamController<SignalingEvent>.broadcast();

  final List<StreamSubscription<Map<String, dynamic>>> _signalSubs = [];
  final List<StreamSubscription<Uint8List>> _audioSubs = [];

  // Tracks which peers are on which transport
  final Map<String, PeerDevice> _activePeers = {};
  CallSession? _currentSession;

  TransportRepositoryImpl({
    required Iterable<ITransportSource> sources,
    required String localDeviceName,
  })  : _sources = {for (final s in sources) s.transportType: s},
        _localDeviceName = localDeviceName;

  /// Initialize all transport sources (start signaling servers, BT listeners).
  Future<void> initializeSources() async {
    for (final source in _sources.values) {
      await source.initialize(_localDeviceName);
    }
    _subscribeToStreams();
  }

  @override
  Stream<Uint8List> get incomingAudioStream => _audioController.stream;

  @override
  Stream<SignalingEvent> get signalingEvents => _signalingController.stream;

  @override
  Future<Result<CallSession>> initiateCall(List<PeerDevice> peers) async {
    try {
      final sessionId = _generateSessionId();
      _activePeers.addAll({for (final p in peers) p.id: p});

      final localIp = await NetworkUtils.getLocalIp() ?? '';

      for (final peer in peers) {
        final source = _sources[peer.transportType];
        if (source == null) {
          return Result.failure(NetworkFailure('No transport source for ${peer.transportType}'));
        }

        await source.connectToPeer(peer.id, _localDeviceName);
        await source.sendSignal(peer.id, {
          'type': AppConstants.sigCallInvite,
          'from': _localDeviceName,
          'fromIp': peer.transportType == TransportType.wifi ? localIp : null,
          'sessionId': sessionId,
        });
      }

      _subscribeToStreams();

      _currentSession = CallSession(
        sessionId: sessionId,
        participantIds: peers.map((p) => p.id).toList(),
        startedAt: DateTime.now(),
        participantNames: {for (final p in peers) p.id: p.name},
      );
      return Result.success(_currentSession!);
    } on TransportException catch (e) {
      await _closeCallConnections();
      return Result.failure(BluetoothFailure(e.message));
    } on SignalingException catch (_) {
      await _closeCallConnections();
      return Result.failure(const NetworkFailure(
        'Could not reach the other device. Ensure both devices are on the same WiFi network.',
      ));
    } catch (e) {
      await _closeCallConnections();
      final msg = e.toString();
      if (msg.contains('connect_error') ||
          msg.contains('read failed') ||
          msg.contains('socket might closed')) {
        return Result.failure(const BluetoothFailure(
          'Bluetooth connection failed. Ensure both devices are paired in Bluetooth settings and try again.',
        ));
      }
      if (msg.contains('Connection timed out') ||
          msg.contains('Connection refused') ||
          msg.contains('SocketException')) {
        return Result.failure(const NetworkFailure(
          'Could not reach the other device. Ensure both devices are on the same WiFi network and try again.',
        ));
      }
      return Result.failure(NetworkFailure(msg));
    }
  }

  @override
  Future<Result<CallSession>> acceptCall(String callerId) async {
    try {
      final peer = _activePeers[callerId];
      if (peer == null) {
        return Result.failure(const NetworkFailure('Unknown caller'));
      }
      
      final source = _sources[peer.transportType];
      if (source == null) {
        return Result.failure(NetworkFailure('No transport source for ${peer.transportType}'));
      }

      final sessionId = _generateSessionId();
      final localIp = await NetworkUtils.getLocalIp() ?? '';

      await source.sendSignal(callerId, {
        'type': AppConstants.sigCallAccept,
        'from': _localDeviceName,
        'fromIp': peer.transportType == TransportType.wifi ? localIp : null,
      });
      await source.startMedia(callerId, isCaller: false);

      _subscribeToStreams();

      _currentSession = CallSession(
        sessionId: sessionId,
        participantIds: [callerId],
        startedAt: DateTime.now(),
        participantNames: {callerId: peer.name},
      );
      return Result.success(_currentSession!);
    } catch (e) {
      return Result.failure(NetworkFailure(e.toString()));
    }
  }

  @override
  Future<Result<void>> declineCall(String callerId) async {
    try {
      final peer = _activePeers[callerId];
      if (peer == null) return Result.success(null);

      final source = _sources[peer.transportType];
      if (source != null) {
        await source.sendSignal(callerId, {
          'type': AppConstants.sigCallDecline,
          'from': _localDeviceName,
        });
        await source.closeAll();
      }

      _activePeers.remove(callerId);
      return Result.success(null);
    } catch (e) {
      return Result.failure(NetworkFailure(e.toString()));
    }
  }

  @override
  Future<Result<void>> endCall(String sessionId) async {
    try {
      for (final entry in _activePeers.entries) {
        final peerId = entry.key;
        final peer = entry.value;
        final source = _sources[peer.transportType];
        
        if (source != null) {
          await source.sendSignal(peerId, {
            'type': AppConstants.sigCallEnd,
            'from': _localDeviceName,
          });
        }
      }
      
      await _closeCallConnections();
      return Result.success(null);
    } catch (e) {
      return Result.failure(NetworkFailure(e.toString()));
    }
  }

  @override
  Future<void> sendAudio(Uint8List audioChunk) async {
    for (final peer in _activePeers.values) {
      final source = _sources[peer.transportType];
      if (source != null) {
        await source.sendAudio(audioChunk);
      }
    }
  }

  // ── Private ──────────────────────────────────────────────────────────────

  void _subscribeToStreams() {
    if (_signalSubs.isEmpty) {
      for (final source in _sources.values) {
        _signalSubs.add(source.signalingStream
            .listen((msg) => _processSignal(msg, source.transportType)));
        _audioSubs.add(source.audioStream.listen(_audioController.add));
      }
    }
  }

  Future<void> _closeCallConnections() async {
    for (final source in _sources.values) {
      try {
        await source.closeAll();
      } catch (_) {}
    }
    _activePeers.clear();
    _currentSession = null;
  }

  Future<void> _processSignal(
    Map<String, dynamic> msg,
    TransportType transportType,
  ) async {
    final type = msg['type'] as String?;
    final from = msg['from'] as String? ?? '';
    final peerId = msg['fromIp'] as String? ?? from;
    final source = _sources[transportType];

    switch (type) {
      case AppConstants.sigCallInvite:
        if (_currentSession != null) {
          // Already in a call — tell the caller we're busy.
          await source?.sendSignal(peerId, {
            'type': AppConstants.sigCallDecline,
            'from': _localDeviceName,
            'reason': 'busy',
          });
          return;
        }
        _activePeers[peerId] = PeerDevice(
          id: peerId,
          name: from,
          transportType: transportType,
          lastSeen: DateTime.now(),
        );
        _signalingController.add(IncomingCallEvent(
          callerId: peerId,
          callerName: from,
          transportLabel:
              transportType == TransportType.wifi ? 'WiFi' : 'Bluetooth',
        ));

      case AppConstants.sigCallAccept:
        // The callee answered — start audio from our side.
        if (_activePeers.containsKey(peerId)) {
          try {
            await source?.startMedia(peerId, isCaller: true);
            _signalingController.add(CallConnectedEvent(peerId: peerId));
          } catch (_) {
            _activePeers.remove(peerId);
            _signalingController.add(
                CallEndedEvent(peerId: peerId, reason: 'error'));
          }
        }

      case AppConstants.sigCallDecline:
      case AppConstants.sigCallEnd:
        if (_activePeers.remove(peerId) == null) return; // unknown / already gone
        if (_activePeers.isEmpty) await _closeCallConnections();
        _signalingController.add(CallEndedEvent(
          peerId: peerId,
          reason: type == AppConstants.sigCallDecline
              ? 'declined'
              : msg['reason'] as String? ?? 'remote_ended',
        ));
    }
  }

  String _generateSessionId() =>
      DateTime.now().millisecondsSinceEpoch.toRadixString(16) +
      Random().nextInt(9999).toString();

  void dispose() {
    for (final sub in _signalSubs) {
      sub.cancel();
    }
    for (final sub in _audioSubs) {
      sub.cancel();
    }
    _signalSubs.clear();
    _audioSubs.clear();

    for (final source in _sources.values) {
      source.dispose();
    }

    _audioController.close();
    _signalingController.close();
  }
}
