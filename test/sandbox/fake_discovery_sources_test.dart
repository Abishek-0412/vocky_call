/// Tests for the fake WiFi and BT discovery sources.
///
/// Verifies that:
///   1. Fake WiFi peers are emitted on schedule.
///   2. Fake BT peers are emitted on schedule.
///   3. Manually injected peers appear on the stream.
///   4. stop() cancels timers (no events after stop).
library fake_discovery_sources_test;

import 'package:flutter_test/flutter_test.dart';
import 'package:vocky_call/domain/value_objects/transport_type.dart';
import 'package:vocky_call/sandbox/fake_bt_discovery_source.dart';
import 'package:vocky_call/sandbox/fake_wifi_discovery_source.dart';
import 'package:vocky_call/domain/entities/peer_device.dart';

void main() {
  group('FakeWifiDiscoverySource', () {
    late FakeWifiDiscoverySource source;

    setUp(() => source = FakeWifiDiscoverySource());
    tearDown(() => source.dispose());

    test('emits fake WiFi peers after start()', () async {
      final peers = <PeerDevice>[];
      final sub = source.peerStream.listen(peers.add);

      await source.startDiscovery('TestDevice');

      // Wait for at least 2 peers (2 × 1.2 s = 2.4 s, give 3 s margin).
      await Future.delayed(const Duration(seconds: 3));

      expect(peers.length, greaterThanOrEqualTo(2));
      expect(peers.every((p) => p.transportType == TransportType.wifi), isTrue);
      await sub.cancel();
    });

    test('injectPeer() emits custom peer immediately', () async {
      final peers = <PeerDevice>[];
      final sub = source.peerStream.listen(peers.add);

      await source.startDiscovery('TestDevice');

      final custom = PeerDevice(
        id: '10.10.10.10',
        name: 'Custom Peer',
        transportType: TransportType.wifi,
        lastSeen: DateTime.now(),
      );
      source.injectPeer(custom);

      await Future.delayed(const Duration(milliseconds: 50));

      expect(peers.any((p) => p.id == '10.10.10.10'), isTrue);
      await sub.cancel();
    });

    test('stop() stops peer emission', () async {
      final peers = <PeerDevice>[];
      final sub = source.peerStream.listen(peers.add);

      await source.startDiscovery('TestDevice');
      await Future.delayed(const Duration(milliseconds: 500));
      await source.stopDiscovery();

      final countAfterStop = peers.length;
      await Future.delayed(const Duration(seconds: 2));

      // No new peers should have arrived after stop.
      expect(peers.length, equals(countAfterStop));
      await sub.cancel();
    });
  });

  group('FakeBtDiscoverySource', () {
    late FakeBtDiscoverySource source;

    setUp(() => source = FakeBtDiscoverySource());
    tearDown(() => source.dispose());

    test('emits fake BT peers after startScan()', () async {
      final peers = <PeerDevice>[];
      final sub = source.peerStream.listen(peers.add);

      await source.startDiscovery('TestDevice');

      // Two peers at 2 s each = 4 s. Give 5 s margin.
      await Future.delayed(const Duration(seconds: 5));

      expect(peers.length, greaterThanOrEqualTo(2));
      expect(
          peers.every((p) => p.transportType == TransportType.bluetooth), isTrue);
      await sub.cancel();
    });

    test('injectPeer() emits custom BT peer', () async {
      final peers = <PeerDevice>[];
      final sub = source.peerStream.listen(peers.add);

      await source.startDiscovery('TestDevice');

      source.injectPeer(PeerDevice(
        id: 'ZZ:ZZ:ZZ:ZZ:ZZ:ZZ',
        name: 'Custom BT',
        transportType: TransportType.bluetooth,
        lastSeen: DateTime.now(),
      ));

      await Future.delayed(const Duration(milliseconds: 50));

      expect(peers.any((p) => p.id == 'ZZ:ZZ:ZZ:ZZ:ZZ:ZZ'), isTrue);
      await sub.cancel();
    });

    test('makeDiscoverable() completes without error', () async {
      await expectLater(
        source.makeDiscoverable(durationSeconds: 10),
        completes,
      );
    });
  });
}
