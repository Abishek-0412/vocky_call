/// Discovery repository implementation.
///
/// Merges discovery streams from generic sources into one unified peer list.
/// Handles peer timeout (removes peers that haven't sent a heartbeat recently).
library discovery_repository_impl;

import 'dart:async';
import 'package:vocky_call/core/errors/failures.dart';
import 'package:vocky_call/core/errors/exceptions.dart';
import 'package:vocky_call/core/result/result.dart';
import 'package:vocky_call/core/constants/app_constants.dart';
import 'package:vocky_call/data/sources/i_discovery_source.dart';
import 'package:vocky_call/data/sources/bluetooth/bt_discovery_source.dart';
import 'package:vocky_call/domain/entities/peer_device.dart';
import 'package:vocky_call/domain/value_objects/transport_type.dart';
import 'package:vocky_call/domain/repositories/i_discovery_repository.dart';

final class DiscoveryRepositoryImpl implements IDiscoveryRepository {
  final Iterable<IDiscoverySource> _sources;
  final IBtDiscoverySource? _btSourceForDiscoverability;

  // Internal state — single source of truth for discovered peers
  final Map<String, PeerDevice> _peers = {};
  final Set<TransportType> _active = {};
  final _peerController = StreamController<List<PeerDevice>>.broadcast();
  Timer? _timeoutTimer;

  final List<StreamSubscription<PeerDevice>> _subs = [];

  DiscoveryRepositoryImpl({
    required Iterable<IDiscoverySource> sources,
    required String localDeviceName,
    IBtDiscoverySource? btSourceForDiscoverability,
  })  : _sources = sources,
        _localDeviceName = localDeviceName,
        _btSourceForDiscoverability = btSourceForDiscoverability;

  final String _localDeviceName;

  @override
  String get localDeviceName => _localDeviceName;

  @override
  Stream<List<PeerDevice>> watchPeers() => _peerController.stream;

  @override
  Set<TransportType> get activeTransports => Set.unmodifiable(_active);

  /// Starts every source on its own, so WiFi-only, Bluetooth-only and
  /// both-on all work. Fails only if no source could start.
  @override
  Future<Result<void>> startDiscovery() async {
    final errors = <String>[];
    for (final source in _sources) {
      _subs.add(source.peerStream.listen(_onPeerDiscovered));
      try {
        await source.startDiscovery(localDeviceName);
        _active.add(source.transportType);
      } on TransportException catch (e) {
        errors.add(e.message);
      } catch (e) {
        errors.add(e.toString());
      }
    }

    // Periodically purge stale peers
    _timeoutTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _purgeTimedOutPeers(),
    );

    if (_active.isEmpty) {
      return Result.failure(NetworkFailure(
        'Turn on Bluetooth or connect to WiFi. (${errors.join(' ')})',
      ));
    }
    return Result.success(null);
  }

  @override
  Future<void> stopDiscovery() async {
    _timeoutTimer?.cancel();
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();

    for (final source in _sources) {
      await source.stopDiscovery();
    }

    _active.clear();
    _peers.clear();
  }

  @override
  Future<Result<void>> refresh() async {
    await stopDiscovery();
    if (!_peerController.isClosed) _peerController.add(const []);
    return startDiscovery();
  }

  @override
  Future<Result<void>> makeDiscoverable({int durationSeconds = 120}) async {
    if (_btSourceForDiscoverability == null) {
      return Result.failure(const BluetoothFailure('Bluetooth source not provided'));
    }
    try {
      await _btSourceForDiscoverability.makeDiscoverable(durationSeconds: durationSeconds);
      return Result.success(null);
    } on TransportException catch (e) {
      return Result.failure(BluetoothFailure(e.message));
    } catch (e) {
      return Result.failure(BluetoothFailure(e.toString()));
    }
  }

  // ── Private ──────────────────────────────────────────────────────────────

  void _onPeerDiscovered(PeerDevice peer) {
    _peers[peer.id] = peer; // update lastSeen
    _peerController.add(List.unmodifiable(_peers.values));
  }

  void _purgeTimedOutPeers() {
    final threshold = DateTime.now().subtract(
      Duration(seconds: AppConstants.peerTimeoutSec),
    );
    final before = _peers.length;
    // Only purge WiFi peers that haven't sent a heartbeat.
    // Bluetooth peers don't have heartbeats and are kept in the list.
    _peers.removeWhere((_, peer) =>
        peer.transportType == TransportType.wifi &&
        peer.lastSeen.isBefore(threshold));
    if (_peers.length != before) {
      _peerController.add(List.unmodifiable(_peers.values));
    }
  }

  void dispose() {
    stopDiscovery();
    _peerController.close();
  }
}
