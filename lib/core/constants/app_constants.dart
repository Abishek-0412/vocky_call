/// Global application constants.
/// Single source of truth for all shared magic values.
library app_constants;

class AppConstants {
  AppConstants._();

  // ── Platform Channel Names ────────────────────────────────────────────────
  static const String multicastLockChannel = 'com.vockycall/multicast_lock';
  static const String audioRoutingChannel = 'com.vockycall/audio_routing';
  static const String btCallChannel = 'com.vockycall/bt_call';
  static const String btCallEventsChannel = 'com.vockycall/bt_call_events';
  static const String btPresenceEventsChannel = 'com.vockycall/bt_presence_events';

  // ── App Identity ──────────────────────────────────────────────
  static const String appName = 'VockyCall';
  static const String appVersion = '1.0.0';

  // ── WiFi Discovery (UDP Multicast) ────────────────────────────
  static const String multicastGroup = '239.255.0.1';
  static const int discoveryPort = 9999;
  static const int signalingPort = 9000;

  /// Heartbeat broadcast interval in seconds.
  static const int heartbeatIntervalSec = 2;

  /// Peer is considered offline after missing this many heartbeats.
  static const int peerTimeoutSec = 6;

  // ── Bluetooth RFCOMM ─────────────────────────────────────────
  /// App-specific RFCOMM service UUID (must match BtCallService.kt).
  static const String rfcommUuid = '7d2c1f4e-8b3a-4c55-9a0e-5f1b6c3d2e10';

  /// App-specific service name for BT discovery filtering.
  static const String btServiceName = 'VockyCall';

  // ── Call Signaling Protocol (text-based, newline-delimited) ──
  static const String sigCallInvite = 'CALL_INVITE';
  static const String sigCallAccept = 'CALL_ACCEPT';
  static const String sigCallDecline = 'CALL_DECLINE';
  static const String sigCallEnd = 'CALL_END';
  static const String sigIceCandidate = 'ICE_CANDIDATE';
  static const String sigSdpOffer = 'SDP_OFFER';
  static const String sigSdpAnswer = 'SDP_ANSWER';
}
