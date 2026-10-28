/// Discovery repository interface.
///
/// Abstracts peer discovery over both WiFi and Bluetooth.
/// Implementations live in the data layer.
library i_discovery_repository;

import 'package:vocky_call/core/result/result.dart';
import 'package:vocky_call/domain/entities/peer_device.dart';
import 'package:vocky_call/domain/value_objects/transport_type.dart';

abstract interface class IDiscoveryRepository {
  /// Live stream of currently visible peers.
  /// Emits a new list whenever a device appears or disappears.
  Stream<List<PeerDevice>> watchPeers();

  /// Start WiFi multicast + Bluetooth scanning.
  Future<Result<void>> startDiscovery();

  /// Stop all discovery and close sockets.
  Future<void> stopDiscovery();

  /// Restart discovery from scratch: clears the list and scans again.
  /// Also picks up WiFi / Bluetooth that was turned on since the last start.
  Future<Result<void>> refresh();

  /// Transports that started successfully (WiFi, Bluetooth or both).
  Set<TransportType> get activeTransports;

  /// Make this device discoverable via Bluetooth for [durationSeconds].
  Future<Result<void>> makeDiscoverable({int durationSeconds = 120});

  /// The local device name (Build.MODEL).
  String get localDeviceName;
}
