/// CallController — StateNotifier managing active call state.
library call_controller;

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vocky_call/domain/repositories/i_transport_repository.dart';
import 'package:vocky_call/domain/use_cases/accept_call_use_case.dart';
import 'package:vocky_call/domain/use_cases/decline_call_use_case.dart';
import 'package:vocky_call/domain/use_cases/end_call_use_case.dart';
import 'package:vocky_call/domain/use_cases/set_audio_output_use_case.dart';
import 'package:vocky_call/domain/use_cases/toggle_mute_use_case.dart';
import 'package:vocky_call/domain/value_objects/audio_output_mode.dart';
import 'package:vocky_call/domain/value_objects/call_state.dart';
import 'package:vocky_call/presentation/features/call/call_ui_state.dart';

export 'call_ui_state.dart';

final class CallController extends StateNotifier<CallUiState> {
  final AcceptCallUseCase _acceptCall;
  final DeclineCallUseCase _declineCall;
  final EndCallUseCase _endCall;
  final ToggleMuteUseCase _toggleMute;
  final SetAudioOutputUseCase _setAudioOutput;
  final ITransportRepository _transportRepo;

  StreamSubscription<SignalingEvent>? _signalingSub;
  Timer? _elapsedTimer;

  CallController({
    required AcceptCallUseCase acceptCall,
    required DeclineCallUseCase declineCall,
    required EndCallUseCase endCall,
    required ToggleMuteUseCase toggleMute,
    required SetAudioOutputUseCase setAudioOutput,
    required ITransportRepository transportRepo,
  })  : _acceptCall = acceptCall,
        _declineCall = declineCall,
        _endCall = endCall,
        _toggleMute = toggleMute,
        _setAudioOutput = setAudioOutput,
        _transportRepo = transportRepo,
        super(const CallUiState.initial()) {
    _listenForIncomingEvents();
  }

  // ── Public Actions ────────────────────────────────────────────────────────

  /// Called when incoming call is shown and user taps "Answer".
  Future<void> answerCall(String callerId) async {
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      await declineCall(callerId);
      return;
    }
    final result = await _acceptCall(callerId);
    result.fold(
      onSuccess: (session) {
        state = state.copyWith(
          callState: CallActive(
            sessionId: session.sessionId,
            participantIds: session.participantIds,
            startedAt: session.startedAt,
            participantNames: session.participantNames,
          ),
        );
        _startElapsedTimer();
      },
      onFailure: (f) => state = state.copyWith(
        callState: const CallEnded(reason: 'error'),
      ),
    );
  }

  /// Called when incoming call is shown and user taps "Decline".
  Future<void> declineCall(String callerId) async {
    await _declineCall(callerId);
    state = state.copyWith(callState: const CallIdle());
  }

  /// End the current active call.
  Future<void> endCall() async {
    final active = state.callState;
    if (active is! CallActive) return;
    await _endCall(active.sessionId);
    _stopElapsedTimer();
    state = state.copyWith(callState: const CallEnded(reason: 'local_ended'));
    await Future.delayed(const Duration(seconds: 1));
    state = state.copyWith(callState: const CallIdle());
  }

  /// Toggle microphone mute.
  Future<void> toggleMute() async {
    final newMuted = !state.audioSettings.isMuted;
    final result = await _toggleMute(muted: newMuted);
    result.fold(
      onSuccess: (_) => state = state.copyWith(
        audioSettings: state.audioSettings.copyWith(isMuted: newMuted),
      ),
      onFailure: (_) {}, // Silently ignore — UI stays unchanged
    );
  }

  /// Change audio output mode.
  Future<void> setAudioOutput(AudioOutputMode mode) async {
    final result = await _setAudioOutput(mode);
    result.fold(
      onSuccess: (_) => state = state.copyWith(
        audioSettings: state.audioSettings.copyWith(outputMode: mode),
      ),
      onFailure: (_) {},
    );
  }

  /// Push-to-talk pressed (walkie-talkie mode).
  Future<void> onPttPressed() async {
    await _toggleMute(muted: false);
    state = state.copyWith(
      audioSettings: state.audioSettings.copyWith(isPttPressed: true),
    );
  }

  /// Push-to-talk released (walkie-talkie mode).
  Future<void> onPttReleased() async {
    await _toggleMute(muted: true);
    state = state.copyWith(
      audioSettings: state.audioSettings.copyWith(isPttPressed: false),
    );
  }

  // Called by HomeController after call initiation succeeds.
  // The timer starts only once the other side answers (CallConnectedEvent).
  void onCallInitiated(
    String sessionId,
    List<String> participantIds, {
    Map<String, String> participantNames = const {},
  }) {
    _stopElapsedTimer();
    state = state.copyWith(
      elapsed: Duration.zero,
      callState: CallActive(
        sessionId: sessionId,
        participantIds: participantIds,
        startedAt: DateTime.now(),
        participantNames: participantNames,
        connected: false,
      ),
    );
  }

  // ── Private ──────────────────────────────────────────────────────────────

  void _listenForIncomingEvents() {
    _signalingSub = _transportRepo.signalingEvents.listen((event) {
      switch (event) {
        case IncomingCallEvent e:
          state = state.copyWith(
            callState: CallRinging(
              callerName: e.callerName,
              callerId: e.callerId,
              transportLabel: e.transportLabel,
            ),
          );
        case CallConnectedEvent _:
          final current = state.callState;
          if (current is CallActive && !current.connected) {
            state = state.copyWith(
              callState:
                  current.copyWith(connected: true, startedAt: DateTime.now()),
            );
            _startElapsedTimer();
          }
        case CallEndedEvent e:
          final current = state.callState;
          if (current is CallIdle || current is CallEnded) return;
          _stopElapsedTimer();
          // Release mic / audio for the call the other side just ended.
          if (current is CallActive) _endCall(current.sessionId);
          state = state.copyWith(
            callState: CallEnded(reason: e.reason),
          );
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted) state = state.copyWith(callState: const CallIdle());
          });
        case PeerAudioLevelEvent e:
          final updated = Map<String, bool>.from(state.speakingMap);
          updated[e.peerId] = e.level > 0.05;
          state = state.copyWith(speakingMap: updated);
      }
    });
  }

  void _startElapsedTimer() {
    _elapsedTimer?.cancel();
    state = state.copyWith(elapsed: Duration.zero);
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      state = state.copyWith(
        elapsed: state.elapsed + const Duration(seconds: 1),
      );
    });
  }

  void _stopElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
  }

  @override
  void dispose() {
    _signalingSub?.cancel();
    _stopElapsedTimer();
    super.dispose();
  }
}
