/// Immutable PeerDevice entity.
///
/// Represents a discovered remote device — either via WiFi or Bluetooth.
/// Equality is based on [id] alone so the same device does not appear twice
/// in the list even if discovered by both transports.
library peer_device;

import 'package:vocky_call/domain/value_objects/transport_type.dart';

final class PeerDevice {
  /// Unique identifier:
  ///   - WiFi  → local IP address (e.g. "192.168.1.5")
  ///   - BT    → Bluetooth MAC address (e.g. "AA:BB:CC:DD:EE:FF")
  final String id;

  /// Human-readable device name (e.g. "Samsung Galaxy S24").
  final String name;

  /// The transport this device was discovered on.
  final TransportType transportType;

  /// Timestamp of last heartbeat received. Used for timeout detection.
  final DateTime lastSeen;

  const PeerDevice({
    required this.id,
    required this.name,
    required this.transportType,
    required this.lastSeen,
  });

  PeerDevice copyWith({
    String? id,
    String? name,
    TransportType? transportType,
    DateTime? lastSeen,
  }) {
    return PeerDevice(
      id: id ?? this.id,
      name: name ?? this.name,
      transportType: transportType ?? this.transportType,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is PeerDevice && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'PeerDevice($name, $id, ${transportType.name})';
}
