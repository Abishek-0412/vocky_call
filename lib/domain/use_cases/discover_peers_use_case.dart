/// Use case: start peer discovery (WiFi + Bluetooth simultaneously).
library discover_peers_use_case;

import 'package:vocky_call/core/result/result.dart';
import 'package:vocky_call/domain/entities/peer_device.dart';
import 'package:vocky_call/domain/repositories/i_discovery_repository.dart';
import 'package:vocky_call/domain/value_objects/transport_type.dart';

final class DiscoverPeersUseCase {
  final IDiscoveryRepository _repository;
  const DiscoverPeersUseCase(this._repository);

  /// Starts discovery and returns a live stream of visible peers.
  Future<Result<Stream<List<PeerDevice>>>> call() async {
    final result = await _repository.startDiscovery();
    return result.map((_) => _repository.watchPeers());
  }

  /// Restarts discovery and returns the same live stream of peers.
  Future<Result<Stream<List<PeerDevice>>>> refresh() async {
    final result = await _repository.refresh();
    return result.map((_) => _repository.watchPeers());
  }

  Set<TransportType> get activeTransports => _repository.activeTransports;
}
