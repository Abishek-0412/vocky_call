/// Fake Bluetooth discovery source for sandbox / testing.
///
/// Emits a set of pre-configured fake BT peers using in-process timers.
/// No real Bluetooth adapter or permissions are required.
library fake_bt_discovery_source;

import 'dart:async';
import 'package:vocky_call/data/sources/bluetooth/bt_discovery_source.dart';
import 'package:vocky_call/domain/entities/peer_device.dart';
import 'package:vocky_call/domain/value_objects/transport_type.dart';

const _kFakeBtPeers = [
  (id: 'AA:BB:CC:DD:EE:01', name: 'Sandbox BT Headset'),
  (id: 'AA:BB:CC:DD:EE:02', name: 'Sandbox BT Watch'),
];

final class FakeBtDiscoverySource implements IBtDiscoverySource {
  final _controller = StreamController<PeerDevice>.broadcast();
  Timer? _scanTimer;
  bool _running = false;

  // Expose the controller so the sandbox control panel can inject peers.
  StreamController<PeerDevice> get controller => _controller;

  @override
  TransportType get transportType => TransportType.bluetooth;

  @override
  Stream<PeerDevice> get peerStream => _controller.stream;

  @override
  Future<void> startDiscovery(String localDeviceName) async {
    if (_running) return;
    _running = true;
    int index = 0;

    // Emit one BT peer every 2 s.
    _scanTimer = Timer.periodic(const Duration(seconds: 2), (t) {
      if (index >= _kFakeBtPeers.length) {
        t.cancel();
        return;
      }
      final p = _kFakeBtPeers[index++];
      _controller.add(PeerDevice(
        id: p.id,
        name: p.name,
        transportType: TransportType.bluetooth,
        lastSeen: DateTime.now(),
      ));
    });
  }

  @override
  Future<void> stopDiscovery() async {
    _running = false;
    _scanTimer?.cancel();
    _scanTimer = null;
  }

  @override
  Future<void> makeDiscoverable({int durationSeconds = 120}) async {
    // No-op in sandbox — device is always "discoverable".
  }

  /// Inject an arbitrary BT peer directly (used by the sandbox control panel).
  void injectPeer(PeerDevice peer) {
    if (!_controller.isClosed) _controller.add(peer);
  }

  void dispose() {
    stopDiscovery();
    _controller.close();
  }
}
