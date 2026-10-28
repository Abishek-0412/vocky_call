import 'dart:async';
import 'package:vocky_call/domain/entities/peer_device.dart';
import 'package:vocky_call/domain/value_objects/transport_type.dart';

abstract interface class IDiscoverySource {
  TransportType get transportType;
  Stream<PeerDevice> get peerStream;
  Future<void> startDiscovery(String localDeviceName);
  Future<void> stopDiscovery();
}
