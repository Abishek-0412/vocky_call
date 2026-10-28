library home_controller_sandbox_test;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vocky_call/core/errors/failures.dart';
import 'package:vocky_call/core/result/result.dart';
import 'package:vocky_call/data/repositories/discovery_repository_impl.dart';
import 'package:vocky_call/domain/entities/peer_device.dart';
import 'package:vocky_call/domain/repositories/i_discovery_repository.dart';
import 'package:vocky_call/domain/use_cases/discover_peers_use_case.dart';
import 'package:vocky_call/domain/use_cases/initiate_call_use_case.dart';
import 'package:vocky_call/domain/use_cases/make_bt_discoverable_use_case.dart';
import 'package:vocky_call/domain/value_objects/transport_type.dart';
import 'package:vocky_call/presentation/features/home/home_controller.dart';
import 'package:vocky_call/sandbox/fake_audio_repository.dart';
import 'package:vocky_call/sandbox/fake_bt_discovery_source.dart';
import 'package:vocky_call/sandbox/fake_bt_transport_source.dart';
import 'package:vocky_call/sandbox/fake_webrtc_transport_source.dart';
import 'package:vocky_call/sandbox/fake_wifi_discovery_source.dart';
import 'package:vocky_call/data/repositories/transport_repository_impl.dart';

// ── Permission channel mock ────────────────────────────────────────────────────
//
// permission_handler uses a MethodChannel. In VM tests there is no real plugin,
// so we register a fake handler that always returns "granted" (value 1).

void _mockPermissions() {
  const channel =
      MethodChannel('flutter.baseflow.com/permissions/methods');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
    // requestPermissions: map each permission int key → 1 (granted)
    if (call.method == 'requestPermissions') {
      final permissions = call.arguments as List<dynamic>;
      return {for (final p in permissions) p as int: 1};
    }
    // checkPermissionStatus, shouldShowRequestPermissionRationale, etc.
    return 1;
  });
}

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Builds an [InitiateCallUseCase] backed entirely by sandbox fakes.
/// (InitiateCallUseCase is final — cannot be subclassed or mocked directly.)
InitiateCallUseCase _buildFakeInitiateCallUseCase() {
  return InitiateCallUseCase(
    TransportRepositoryImpl(
      sources: [
        FakeWebRtcTransportSource(),
        FakeBtTransportSource(),
      ],
      localDeviceName: 'TestDevice',
    ),
    FakeAudioRepository(),
  );
}

/// Build a real [DiscoveryRepositoryImpl] backed by fake sources.
IDiscoveryRepository _buildFakeDiscoveryRepo() {
  final btSource = FakeBtDiscoverySource();
  return DiscoveryRepositoryImpl(
    sources: [
      FakeWifiDiscoverySource(),
      btSource,
    ],
    localDeviceName: 'TestDevice',
    btSourceForDiscoverability: btSource,
  );
}

HomeController _buildController(
  IDiscoveryRepository discoveryRepo, {
  bool Function()? isInCall,
}) {
  return HomeController(
    discoverPeers: DiscoverPeersUseCase(discoveryRepo),
    initiateCall: _buildFakeInitiateCallUseCase(),
    makeBtDiscoverable: MakeBtDiscoverableUseCase(discoveryRepo),
    isInCall: isInCall,
  );
}

/// Wraps a real repository and counts refresh() calls.
final class _CountingRepo implements IDiscoveryRepository {
  final IDiscoveryRepository inner;
  int refreshes = 0;

  /// When set, makeDiscoverable fails (user tapped Deny).
  bool denyVisibility = false;
  _CountingRepo(this.inner);

  @override
  Future<Result<void>> refresh() {
    refreshes++;
    return inner.refresh();
  }

  @override
  Stream<List<PeerDevice>> watchPeers() => inner.watchPeers();
  @override
  Future<Result<void>> startDiscovery() => inner.startDiscovery();
  @override
  Future<void> stopDiscovery() => inner.stopDiscovery();
  @override
  Future<Result<void>> makeDiscoverable({int durationSeconds = 120}) async {
    if (denyVisibility) {
      return Result.failure(
          const BluetoothFailure('Bluetooth visibility was not allowed.'));
    }
    return inner.makeDiscoverable(durationSeconds: durationSeconds);
  }
  @override
  Set<TransportType> get activeTransports => inner.activeTransports;
  @override
  String get localDeviceName => inner.localDeviceName;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HomeController — sandbox fakes', () {
    late IDiscoveryRepository repo;
    late HomeController controller;

    setUp(() async {
      _mockPermissions();
      repo = _buildFakeDiscoveryRepo();
      controller = _buildController(repo);
      // Yield to the microtask queue so _startDiscovery's async chain
      // registers its callbacks before each test body runs.
      await Future.delayed(const Duration(milliseconds: 50));
    });

    tearDown(() async {
      // Let any in-flight async callbacks flush before dispose.
      await Future.delayed(const Duration(milliseconds: 50));
      controller.dispose();
    });

    test('peers list populates within 4 s of construction', () async {
      // The fake WiFi source emits its first peer after ~1.2 s.
      await Future.delayed(const Duration(seconds: 4));
      expect(controller.state.peers, isNotEmpty);
      expect(
        controller.state.peers.any(
          (p) => p.transportType == TransportType.wifi,
        ),
        isTrue,
      );
    });

    test('discoveryStatus transitions to active after startDiscovery succeeds',
        () async {
      await Future.delayed(const Duration(seconds: 2));
      expect(
        controller.state.discoveryStatus,
        anyOf(DiscoveryStatus.scanning, DiscoveryStatus.active),
      );
    });

    test('togglePeerSelection adds and removes peer IDs', () async {
      const peerId = '192.168.1.10';
      controller.togglePeerSelection(peerId);
      expect(controller.state.selectedPeerIds.contains(peerId), isTrue);

      controller.togglePeerSelection(peerId);
      expect(controller.state.selectedPeerIds.contains(peerId), isFalse);
    });

    test('clearError resets errorMessage to null', () async {
      final stateWithError =
          controller.state.copyWith(errorMessage: 'test error');
      expect(stateWithError.errorMessage, 'test error');

      final cleared = stateWithError.copyWith(clearError: true);
      expect(cleared.errorMessage, isNull);
    });

    test('canStartGroupCall is false with fewer than 2 selected peers',
        () async {
      controller.togglePeerSelection('peer-1');
      expect(controller.state.canStartGroupCall, isFalse);
    });

    test('canStartGroupCall is true with 2+ selected peers', () async {
      controller.togglePeerSelection('peer-1');
      controller.togglePeerSelection('peer-2');
      expect(controller.state.canStartGroupCall, isTrue);
    });

    test('shows both transports as active', () async {
      expect(controller.state.activeTransports,
          {TransportType.wifi, TransportType.bluetooth});
    });
  });

  group('HomeController — refresh', () {
    setUp(_mockPermissions);

    test('refresh rescans when not in a call', () async {
      final repo = _CountingRepo(_buildFakeDiscoveryRepo());
      final controller = _buildController(repo);
      await Future.delayed(const Duration(milliseconds: 50));

      await controller.refresh();

      expect(repo.refreshes, 1);
      expect(controller.state.discoveryStatus, DiscoveryStatus.active);
      controller.dispose();
    });

    test('refresh does nothing during a call', () async {
      final repo = _CountingRepo(_buildFakeDiscoveryRepo());
      final controller = _buildController(repo, isInCall: () => true);
      await Future.delayed(const Duration(milliseconds: 50));

      await controller.refresh();

      expect(repo.refreshes, 0);
      controller.dispose();
    });

    test('Make Visible: allowed shows Visible', () async {
      final repo = _CountingRepo(_buildFakeDiscoveryRepo());
      final controller = _buildController(repo);
      await controller.makeBtDiscoverable();

      expect(controller.state.isDiscoverableBt, isTrue);
      controller.dispose();
    });

    test('Make Visible: denied stays hidden and explains why', () async {
      final repo = _CountingRepo(_buildFakeDiscoveryRepo())
        ..denyVisibility = true;
      final controller = _buildController(repo);
      await controller.makeBtDiscoverable();

      expect(controller.state.isDiscoverableBt, isFalse);
      expect(controller.state.errorMessage, contains('not allowed'));
      controller.dispose();
    });

    test('auto-refresh interval is 20 seconds', () {
      expect(HomeController.autoRefreshInterval, const Duration(seconds: 20));
    });
  });
}
