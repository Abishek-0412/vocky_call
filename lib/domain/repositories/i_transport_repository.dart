/// Transport repository interface.
///
/// Abstracts the signaling and peer connection lifecycle over
/// both WiFi (WebRTC) and Bluetooth (RFCOMM).
library i_transport_repository;

import 'dart:typed_data';
import 'package:vocky_call/core/result/result.dart';
import 'package:vocky_call/domain/entities/peer_device.dart';
import 'package:vocky_call/domain/entities/call_session.dart';

abstract interface class ITransportRepository {
  /// Initiate a call to one or more peers.
  /// Returns a [CallSession] on success.
  Future<Result<CallSession>> initiateCall(List<PeerDevice> peers);

  /// Accept an incoming call from [callerId].
  Future<Result<CallSession>> acceptCall(String callerId);

  /// Decline an incoming call from [callerId].
  Future<Result<void>> declineCall(String callerId);

  /// End the current active call.
  Future<Result<void>> endCall(String sessionId);

  /// Stream of raw audio bytes received from all remote peers.
  Stream<Uint8List> get incomingAudioStream;

  /// Send raw audio bytes to all connected peers.
  Future<void> sendAudio(Uint8List audioChunk);

  /// Stream of signaling events (e.g. incoming call invites, ICE candidates).
  Stream<SignalingEvent> get signalingEvents;
}

/// Signaling events emitted by the transport layer.
sealed class SignalingEvent {
  const SignalingEvent();
}

final class IncomingCallEvent extends SignalingEvent {
  final String callerId;
  final String callerName;
  final String transportLabel;
  const IncomingCallEvent({
    required this.callerId,
    required this.callerName,
    required this.transportLabel,
  });
}

/// The callee answered our outgoing call.
final class CallConnectedEvent extends SignalingEvent {
  final String peerId;
  const CallConnectedEvent({required this.peerId});
}

final class CallEndedEvent extends SignalingEvent {
  final String peerId;
  final String reason;
  const CallEndedEvent({required this.peerId, required this.reason});
}

final class PeerAudioLevelEvent extends SignalingEvent {
  final String peerId;
  final double level; // 0.0–1.0
  const PeerAudioLevelEvent({required this.peerId, required this.level});
}
