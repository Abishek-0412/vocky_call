library discovery_repository_test;

import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocky_call/core/errors/exceptions.dart';
import 'package:vocky_call/data/repositories/discovery_repository_impl.dart';
import 'package:vocky_call/data/sources/i_discovery_source.dart';
import 'package:vocky_call/domain/entities/peer_device.dart';
import 'package:vocky_call/domain/value_objects/transport_type.dart';

class MockDiscoverySource implements IDiscoverySource {
  final _controller = StreamController<PeerDevice>.broadcast();
  @override
  final TransportType transportType;

  MockDiscoverySource(this.transportType);

  /// When set, startDiscovery throws (e.g. WiFi not connected).
  String? failWith;
  int starts = 0;

  @override
  Stream<PeerDevice> get peerStream => _controller.stream;

  @override
  Future<void> startDiscovery(String localDeviceName) async {
    starts++;
    if (failWith != null) throw TransportException(failWith!);
  }

  @override
  Future<void> stopDiscovery() async {}

  void emitPeer(PeerDevice peer) {
    _controller.add(peer);
  }

  void dispose() {
    _controller.close();
  }
}

void main() {
  group('DiscoveryRepositoryImpl Unit Tests', () {
    late MockDiscoverySource wifiSource;
    late MockDiscoverySource btSource;
    late DiscoveryRepositoryImpl repository;

    setUp(() {
      wifiSource = MockDiscoverySource(TransportType.wifi);
      btSource = MockDiscoverySource(TransportType.bluetooth);
      repository = DiscoveryRepositoryImpl(
        sources: [wifiSource, btSource],
        localDeviceName: 'TestDevice',
      );
    });

    tearDown(() {
      wifiSource.dispose();
      btSource.dispose();
      repository.dispose();
    });

    test('merges peers from WiFi and Bluetooth sources', () async {
      final stream = repository.watchPeers();
      final latestPeers = <List<PeerDevice>>[];
      final sub = stream.listen(latestPeers.add);

      await repository.startDiscovery();

      final wifiPeer = PeerDevice(
        id: '192.168.1.50',
        name: 'WiFi Phone',
        transportType: TransportType.wifi,
        lastSeen: DateTime.now(),
      );
      final btPeer = PeerDevice(
        id: 'AA:BB:CC:DD:EE:FF',
        name: 'BT Phone',
        transportType: TransportType.bluetooth,
        lastSeen: DateTime.now(),
      );

      wifiSource.emitPeer(wifiPeer);
      btSource.emitPeer(btPeer);

      await Future.delayed(const Duration(milliseconds: 50));

      expect(latestPeers.isNotEmpty, isTrue);
      final currentList = latestPeers.last;
      expect(currentList.length, equals(2));
      expect(currentList.any((p) => p.id == '192.168.1.50'), isTrue);
      expect(currentList.any((p) => p.id == 'AA:BB:CC:DD:EE:FF'), isTrue);

      await sub.cancel();
    });

    test('retains Bluetooth peers while purging stale WiFi peers', () async {
      final stream = repository.watchPeers();
      final latestPeers = <List<PeerDevice>>[];
      final sub = stream.listen(latestPeers.add);

      await repository.startDiscovery();

      final staleWifiPeer = PeerDevice(
        id: '192.168.1.99',
        name: 'Stale WiFi Device',
        transportType: TransportType.wifi,
        lastSeen: DateTime.now().subtract(const Duration(seconds: 10)),
      );
      final btPeer = PeerDevice(
        id: '11:22:33:44:55:66',
        name: 'Visible BT Device',
        transportType: TransportType.bluetooth,
        lastSeen: DateTime.now().subtract(const Duration(seconds: 10)),
      );

      wifiSource.emitPeer(staleWifiPeer);
      btSource.emitPeer(btPeer);

      await Future.delayed(const Duration(milliseconds: 50));
      expect(latestPeers.last.length, equals(2));

      // Wait for repository's periodic purge timer (2 s interval)
      await Future.delayed(const Duration(seconds: 3));

      // Stale WiFi peer should be purged, but BT peer MUST be retained!
      final currentList = latestPeers.last;
      expect(currentList.any((p) => p.id == '192.168.1.99'), isFalse);
      expect(currentList.any((p) => p.id == '11:22:33:44:55:66'), isTrue);

      await sub.cancel();
    });

    test('Bluetooth still works when WiFi cannot start', () async {
      wifiSource.failWith = 'Not connected to WiFi.';
      final result = await repository.startDiscovery();

      expect(result.isSuccess, isTrue);
      expect(repository.activeTransports, {TransportType.bluetooth});
    });

    test('WiFi still works when Bluetooth is off', () async {
      btSource.failWith = 'Bluetooth is off.';
      final result = await repository.startDiscovery();

      expect(result.isSuccess, isTrue);
      expect(repository.activeTransports, {TransportType.wifi});
    });

    test('fails only when neither WiFi nor Bluetooth can start', () async {
      wifiSource.failWith = 'Not connected to WiFi.';
      btSource.failWith = 'Bluetooth is off.';
      final result = await repository.startDiscovery();

      expect(result.isFailure, isTrue);
      expect(repository.activeTransports, isEmpty);
    });

    test('refresh clears the list, restarts sources and picks up WiFi',
        () async {
      final latestPeers = <List<PeerDevice>>[];
      final sub = repository.watchPeers().listen(latestPeers.add);
      wifiSource.failWith = 'Not connected to WiFi.';
      await repository.startDiscovery();
      btSource.emitPeer(PeerDevice(
        id: 'AA:BB:CC:DD:EE:FF',
        name: 'BT Phone',
        transportType: TransportType.bluetooth,
        lastSeen: DateTime.now(),
      ));
      await Future.delayed(const Duration(milliseconds: 20));
      expect(latestPeers.last, hasLength(1));

      wifiSource.failWith = null; // user connected to WiFi
      final result = await repository.refresh();
      await Future.delayed(const Duration(milliseconds: 20));

      expect(result.isSuccess, isTrue);
      expect(latestPeers.last, isEmpty);
      expect(wifiSource.starts, 2);
      expect(btSource.starts, 2);
      expect(repository.activeTransports,
          {TransportType.wifi, TransportType.bluetooth});

      // Peers found after the refresh still reach the list.
      btSource.emitPeer(PeerDevice(
        id: 'AA:BB:CC:DD:EE:FF',
        name: 'BT Phone',
        transportType: TransportType.bluetooth,
        lastSeen: DateTime.now(),
      ));
      await Future.delayed(const Duration(milliseconds: 20));
      expect(latestPeers.last, hasLength(1));
      await sub.cancel();
    });
  });
}
