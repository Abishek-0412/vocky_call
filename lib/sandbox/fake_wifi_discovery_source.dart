/// Fake WiFi discovery source for sandbox / testing.
///
/// Emits a set of pre-configured fake WiFi peers using in-process timers.
/// No real UDP socket or multicast is opened. Designed to implement
/// [IWifiDiscoverySource] without requiring actual hardware or permissions.
library fake_wifi_discovery_source;

import 'dart:async';
import 'package:vocky_call/data/sources/wifi/wifi_discovery_source.dart';
import 'package:vocky_call/domain/entities/peer_device.dart';
import 'package:vocky_call/domain/value_objects/transport_type.dart';

/// Predefined fake WiFi peers surfaced by the sandbox.
const _kFakePeers = [
  (id: '192.168.1.10', name: 'Sandbox Phone A'),
  (id: '192.168.1.11', name: 'Sandbox Tablet B'),
  (id: '192.168.1.12', name: 'Sandbox Laptop C'),
];

final class FakeWifiDiscoverySource implements IWifiDiscoverySource {
  final _controller = StreamController<PeerDevice>.broadcast();

  Timer? _emitTimer;
  Timer? _dropTimer;
  int _peerIndex = 0;
  bool _running = false;

  // Expose the controller so the sandbox control panel can inject peers.
  StreamController<PeerDevice> get controller => _controller;

  @override
  TransportType get transportType => TransportType.wifi;

  @override
  Stream<PeerDevice> get peerStream => _controller.stream;

  @override
  Future<void> startDiscovery(String localDeviceName) async {
    if (_running) return;
    _running = true;
    _peerIndex = 0;

    // Emit one fake peer every 1.2 s until all are discovered.
    _emitTimer = Timer.periodic(const Duration(milliseconds: 1200), (t) {
      if (_peerIndex >= _kFakePeers.length) {
        t.cancel();
        return;
      }
      final p = _kFakePeers[_peerIndex++];
      _controller.add(PeerDevice(
        id: p.id,
        name: p.name,
        transportType: TransportType.wifi,
        lastSeen: DateTime.now(),
      ));
    });

    // After 8 s, simulate a peer going offline (re-emit with stale lastSeen
    // — the repository will handle timeout removal).
    _dropTimer = Timer(const Duration(seconds: 8), () {
      // Re-emit the third peer as stale to signal churn.
      _controller.add(PeerDevice(
        id: _kFakePeers[2].id,
        name: _kFakePeers[2].name,
        transportType: TransportType.wifi,
        // Stale timestamp — repository's TTL check should drop it.
        lastSeen: DateTime.now().subtract(const Duration(seconds: 60)),
      ));
    });
  }

  @override
  Future<void> stopDiscovery() async {
    _running = false;
    _emitTimer?.cancel();
    _dropTimer?.cancel();
    _emitTimer = null;
    _dropTimer = null;
  }

  /// Inject an arbitrary peer directly (used by the sandbox control panel).
  void injectPeer(PeerDevice peer) {
    if (!_controller.isClosed) _controller.add(peer);
  }

  void dispose() {
    stopDiscovery();
    _controller.close();
  }
}
