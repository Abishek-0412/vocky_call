/// Immutable CallSession entity — represents an active or completed call.
library call_session;

final class CallSession {
  final String sessionId;
  final List<String> participantIds; // peer device IDs
  final DateTime startedAt;

  /// peer device ID → display name
  final Map<String, String> participantNames;

  const CallSession({
    required this.sessionId,
    required this.participantIds,
    required this.startedAt,
    this.participantNames = const {},
  });

  @override
  String toString() =>
      'CallSession($sessionId, participants: ${participantIds.length})';
}
