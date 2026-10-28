/// Domain-level failures — sealed class hierarchy.
///
/// All failure types are defined here. No raw exceptions cross layer boundaries.
library failures;

sealed class Failure {
  final String message;
  const Failure(this.message);

  @override
  String toString() => '$runtimeType: $message';
}

/// WiFi/network-related failures.
final class NetworkFailure extends Failure {
  const NetworkFailure(super.message);
}

/// Bluetooth-related failures.
final class BluetoothFailure extends Failure {
  const BluetoothFailure(super.message);
}

/// Audio capture or playback failures.
final class AudioFailure extends Failure {
  const AudioFailure(super.message);
}

/// Runtime permission was denied.
final class PermissionFailure extends Failure {
  const PermissionFailure(super.message);
}

/// WebRTC signaling or peer connection failures.
final class SignalingFailure extends Failure {
  const SignalingFailure(super.message);
}

/// An unexpected internal error.
final class UnknownFailure extends Failure {
  const UnknownFailure(super.message);
}
