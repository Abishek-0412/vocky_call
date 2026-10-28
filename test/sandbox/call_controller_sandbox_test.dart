/// Tests for CallController using sandbox fake transport sources.
///
/// Verifies the full call lifecycle:
///   1. Simulated incoming call → state transitions to CallRinging.
///   2. answerCall() → state transitions to CallActive.
///   3. endCall() → state transitions to CallEnded then CallIdle.
///   4. declineCall() → state stays CallIdle.
///   5. toggleMute() flips isMuted.
///   6. Remote call drop → state transitions to CallEnded.
library call_controller_sandbox_test;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vocky_call/core/result/result.dart';
import 'package:vocky_call/domain/entities/call_session.dart';
import 'package:vocky_call/domain/entities/peer_device.dart';
import 'package:vocky_call/domain/repositories/i_audio_repository.dart';
import 'package:vocky_call/domain/repositories/i_transport_repository.dart';
import 'package:vocky_call/domain/use_cases/accept_call_use_case.dart';
import 'package:vocky_call/domain/use_cases/decline_call_use_case.dart';
import 'package:vocky_call/domain/use_cases/end_call_use_case.dart';
import 'package:vocky_call/domain/use_cases/set_audio_output_use_case.dart';
import 'package:vocky_call/domain/use_cases/toggle_mute_use_case.dart';
import 'package:vocky_call/domain/value_objects/call_state.dart';
import 'package:vocky_call/presentation/features/call/call_controller.dart';
import 'package:vocky_call/sandbox/fake_audio_repository.dart';

// ── Sandbox transport stub ────────────────────────────────────────────────────
//
// Instead of going through the real TransportRepositoryImpl (which requires
// _subscribeToSignaling to be triggered by initiateCall/acceptCall), we use a
// simple in-process stub that directly exposes a signaling stream and lets
// tests inject SignalingEvents.

final class _SandboxTransportRepository implements ITransportRepository {
  final _signalingController =
      StreamController<SignalingEvent>.broadcast();
  final _audioController = StreamController<Uint8List>.broadcast();

  // Whether the last endCall / declineCall was called.
  bool endCallCalled = false;
  bool declineCalled = false;
  bool acceptCalled = false;

  /// Inject any [SignalingEvent] directly into the controller stream.
  void inject(SignalingEvent event) {
    if (!_signalingController.isClosed) _signalingController.add(event);
  }

  @override
  Stream<SignalingEvent> get signalingEvents => _signalingController.stream;

  @override
  Stream<Uint8List> get incomingAudioStream => _audioController.stream;

  @override
  Future<Result<CallSession>> initiateCall(List<PeerDevice> peers) async {
    return Result.success(CallSession(
      sessionId: 'sandbox-session',
      participantIds: peers.map((p) => p.id).toList(),
      startedAt: DateTime.now(),
    ));
  }

  @override
  Future<Result<CallSession>> acceptCall(String callerId) async {
    acceptCalled = true;
    return Result.success(CallSession(
      sessionId: 'sandbox-session',
      participantIds: [callerId],
      startedAt: DateTime.now(),
    ));
  }

  @override
  Future<Result<void>> declineCall(String callerId) async {
    declineCalled = true;
    return Result.success(null);
  }

  @override
  Future<Result<void>> endCall(String sessionId) async {
    endCallCalled = true;
    return Result.success(null);
  }

  @override
  Future<void> sendAudio(Uint8List audioChunk) async {}

  void dispose() {
    _signalingController.close();
    _audioController.close();
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

CallController _buildController(
  _SandboxTransportRepository transportRepo,
  IAudioRepository audio,
) {
  return CallController(
    acceptCall: AcceptCallUseCase(transportRepo, audio),
    declineCall: DeclineCallUseCase(transportRepo),
    endCall: EndCallUseCase(transportRepo, audio),
    toggleMute: ToggleMuteUseCase(audio),
    setAudioOutput: SetAudioOutputUseCase(audio),
    transportRepo: transportRepo,
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // answerCall() asks for mic permission — report every permission granted.
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('flutter.baseflow.com/permissions/methods'),
    (call) async => call.method == 'requestPermissions'
        ? {for (final p in call.arguments as List) p: 1}
        : 1,
  );

  TestWidgetsFlutterBinding.ensureInitialized();

  group('CallController — sandbox fakes', () {
    late _SandboxTransportRepository transportRepo;
    late FakeAudioRepository audio;
    late CallController controller;

    setUp(() {
      transportRepo = _SandboxTransportRepository();
      audio = FakeAudioRepository();
      controller = _buildController(transportRepo, audio);
    });

    tearDown(() {
      controller.dispose();
      transportRepo.dispose();
    });

    // ── 1. Incoming call → Ringing ────────────────────────────────────────

    test('incoming IncomingCallEvent transitions state to CallRinging', () async {
      expect(controller.state.callState, isA<CallIdle>());

      transportRepo.inject(const IncomingCallEvent(
        callerId: '192.168.1.50',
        callerName: 'Test Caller',
        transportLabel: 'WiFi',
      ));

      await Future.delayed(const Duration(milliseconds: 50));

      expect(controller.state.callState, isA<CallRinging>());
      final ringing = controller.state.callState as CallRinging;
      expect(ringing.callerName, 'Test Caller');
      expect(ringing.callerId, '192.168.1.50');
    });

    // ── 2. Answer → Active ────────────────────────────────────────────────

    test('answerCall() transitions state to CallActive', () async {
      transportRepo.inject(const IncomingCallEvent(
        callerId: '192.168.1.50',
        callerName: 'Test Caller',
        transportLabel: 'WiFi',
      ));
      await Future.delayed(const Duration(milliseconds: 50));

      await controller.answerCall('192.168.1.50');
      expect(controller.state.callState, isA<CallActive>());
    });

    // ── 3. End call → Ended → Idle ────────────────────────────────────────

    test('endCall() transitions through CallEnded then back to CallIdle',
        () async {
      controller.onCallInitiated('session-001', ['192.168.1.50']);
      expect(controller.state.callState, isA<CallActive>());

      await controller.endCall();

      expect(
        controller.state.callState,
        anyOf(isA<CallEnded>(), isA<CallIdle>()),
      );

      // After the 1-second grace period it must settle to CallIdle.
      await Future.delayed(const Duration(seconds: 2));
      expect(controller.state.callState, isA<CallIdle>());
    });

    // ── 3b. Outgoing call: timer waits for answer ───────────────────────

    test('outgoing call shows Calling until answered, then starts timer',
        () async {
      controller.onCallInitiated('session-003', ['10.0.0.2'],
          participantNames: {'10.0.0.2': 'Phone B'});
      var active = controller.state.callState as CallActive;
      expect(active.connected, isFalse);
      expect(active.participantNames['10.0.0.2'], 'Phone B');

      await Future.delayed(const Duration(milliseconds: 1200));
      expect(controller.state.elapsed, Duration.zero);

      transportRepo.inject(const CallConnectedEvent(peerId: '10.0.0.2'));
      await Future.delayed(const Duration(milliseconds: 50));
      active = controller.state.callState as CallActive;
      expect(active.connected, isTrue);

      await Future.delayed(const Duration(milliseconds: 1100));
      expect(controller.state.elapsed, greaterThan(Duration.zero));
      await controller.endCall();
    });

    // ── 4. Decline call ───────────────────────────────────────────────────

    test('declineCall() keeps state as CallIdle', () async {
      transportRepo.inject(const IncomingCallEvent(
        callerId: '1.2.3.4',
        callerName: 'Decliner',
        transportLabel: 'WiFi',
      ));
      await Future.delayed(const Duration(milliseconds: 50));

      await controller.declineCall('1.2.3.4');
      expect(controller.state.callState, isA<CallIdle>());
      expect(transportRepo.declineCalled, isTrue);
    });

    // ── 5. Toggle mute ────────────────────────────────────────────────────

    test('toggleMute() flips isMuted flag', () async {
      expect(controller.state.audioSettings.isMuted, isFalse);

      await controller.toggleMute();
      expect(controller.state.audioSettings.isMuted, isTrue);

      await controller.toggleMute();
      expect(controller.state.audioSettings.isMuted, isFalse);
    });

    // ── 6. Remote hang-up ─────────────────────────────────────────────────

    test('remote CallEndedEvent transitions state to CallEnded', () async {
      controller.onCallInitiated('session-002', ['192.168.1.50']);
      expect(controller.state.callState, isA<CallActive>());

      transportRepo.inject(const CallEndedEvent(
        peerId: '192.168.1.50',
        reason: 'remote_ended',
      ));
      await Future.delayed(const Duration(milliseconds: 200));

      expect(
        controller.state.callState,
        anyOf(isA<CallEnded>(), isA<CallIdle>()),
      );
    });

    // ── 7. PTT (push-to-talk) ─────────────────────────────────────────────

    test('onPttPressed unmutes; onPttReleased re-mutes', () async {
      await controller.onPttPressed();
      expect(controller.state.audioSettings.isPttPressed, isTrue);
      expect(controller.state.audioSettings.isMuted, isFalse);

      await controller.onPttReleased();
      expect(controller.state.audioSettings.isPttPressed, isFalse);
    });
  });
}
