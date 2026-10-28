/// Sealed call state — single source of truth for where the app is in the call lifecycle.
library call_state;

sealed class CallState {
  const CallState();
}

/// No active call. App is on home screen.
final class CallIdle extends CallState {
  const CallIdle();
}

/// This device is ringing — an incoming invite was received.
final class CallRinging extends CallState {
  final String callerName;
  final String callerId;
  final String transportLabel;
  const CallRinging({
    required this.callerName,
    required this.callerId,
    required this.transportLabel,
  });
}

/// Audio call is live, or (when [connected] is false) we are calling and
/// waiting for the other side to answer.
final class CallActive extends CallState {
  final String sessionId;
  final List<String> participantIds;
  final DateTime startedAt;

  /// peer device ID → display name
  final Map<String, String> participantNames;
  final bool connected;

  const CallActive({
    required this.sessionId,
    required this.participantIds,
    required this.startedAt,
    this.participantNames = const {},
    this.connected = true,
  });

  CallActive copyWith({bool? connected, DateTime? startedAt}) => CallActive(
        sessionId: sessionId,
        participantIds: participantIds,
        startedAt: startedAt ?? this.startedAt,
        participantNames: participantNames,
        connected: connected ?? this.connected,
      );
}

/// Call ended (local or remote).
final class CallEnded extends CallState {
  final String reason; // 'local_ended' | 'remote_ended' | 'declined' | 'error'
  const CallEnded({required this.reason});
}
