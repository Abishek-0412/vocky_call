/// Infrastructure-level exceptions caught in the data layer and mapped to Failures.
library exceptions;

class TransportException implements Exception {
  final String message;
  const TransportException(this.message);
  @override
  String toString() => 'TransportException: $message';
}

class BluetoothException implements Exception {
  final String message;
  const BluetoothException(this.message);
  @override
  String toString() => 'BluetoothException: $message';
}

class AudioException implements Exception {
  final String message;
  const AudioException(this.message);
  @override
  String toString() => 'AudioException: $message';
}

class SignalingException implements Exception {
  final String message;
  const SignalingException(this.message);
  @override
  String toString() => 'SignalingException: $message';
}
