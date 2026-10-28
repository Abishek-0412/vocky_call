/// CallUiState — immutable state for the active call screen.
/// Single source of truth for call lifecycle and audio settings.
library call_ui_state;

import 'package:vocky_call/domain/entities/audio_settings.dart';
import 'package:vocky_call/domain/entities/call_session.dart';
import 'package:vocky_call/domain/value_objects/call_state.dart';

final class CallUiState {
  final CallState callState;
  final AudioSettings audioSettings;

  /// Maps peerId → true if the peer is currently speaking.
  final Map<String, bool> speakingMap;

  /// Elapsed duration (updated by a timer in the controller).
  final Duration elapsed;

  const CallUiState({
    this.callState = const CallIdle(),
    this.audioSettings = const AudioSettings(),
    this.speakingMap = const {},
    this.elapsed = Duration.zero,
  });

  const CallUiState.initial() : this();

  CallUiState copyWith({
    CallState? callState,
    AudioSettings? audioSettings,
    Map<String, bool>? speakingMap,
    Duration? elapsed,
  }) {
    return CallUiState(
      callState: callState ?? this.callState,
      audioSettings: audioSettings ?? this.audioSettings,
      speakingMap: speakingMap ?? this.speakingMap,
      elapsed: elapsed ?? this.elapsed,
    );
  }

  bool get isCallActive => callState is CallActive;
  bool get isRinging => callState is CallRinging;
  CallSession? get session =>
      callState is CallActive ? (callState as CallActive).let(_toSession) : null;

  CallSession _toSession(CallActive active) => CallSession(
        sessionId: active.sessionId,
        participantIds: active.participantIds,
        startedAt: active.startedAt,
      );
}

extension _Let<T> on T {
  R let<R>(R Function(T) fn) => fn(this);
}
