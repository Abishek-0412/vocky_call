/// HomeController — StateNotifier managing home screen state.
///
/// All interactions from HomeScreen go through this controller.
/// No business logic lives in the UI.
library home_controller;

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vocky_call/domain/entities/call_session.dart';
import 'package:vocky_call/domain/entities/peer_device.dart';
import 'package:vocky_call/domain/use_cases/discover_peers_use_case.dart';
import 'package:vocky_call/domain/use_cases/initiate_call_use_case.dart';
import 'package:vocky_call/domain/use_cases/make_bt_discoverable_use_case.dart';
import 'package:vocky_call/core/result/result.dart';
import 'package:vocky_call/presentation/features/home/home_state.dart';

export 'home_state.dart';

final class HomeController extends StateNotifier<HomeState> {
  final DiscoverPeersUseCase _discoverPeers;
  final InitiateCallUseCase _initiateCall;
  final MakeBtDiscoverableUseCase _makeBtDiscoverable;
  final void Function(CallSession session)? _onCallInitiated;
  final bool Function() _isInCall;

  /// While nothing is found, rescan this often (never during a call).
  static const autoRefreshInterval = Duration(seconds: 20);

  StreamSubscription<List<PeerDevice>>? _peersSub;
  Timer? _autoRefreshTimer;
  Timer? _visibleTimer;
  bool _permissionsGranted = false;
  bool _refreshing = false;

  HomeController({
    required DiscoverPeersUseCase discoverPeers,
    required InitiateCallUseCase initiateCall,
    required MakeBtDiscoverableUseCase makeBtDiscoverable,
    void Function(CallSession session)? onCallInitiated,
    bool Function()? isInCall,
  })  : _discoverPeers = discoverPeers,
        _initiateCall = initiateCall,
        _makeBtDiscoverable = makeBtDiscoverable,
        _onCallInitiated = onCallInitiated,
        _isInCall = isInCall ?? (() => false),
        super(const HomeState.initial()) {
    _startDiscovery();
    _autoRefreshTimer = Timer.periodic(autoRefreshInterval, (_) {
      if (_permissionsGranted && state.peers.isEmpty) refresh();
    });
  }

  /// Rescan for devices. Does nothing during a call.
  Future<void> refresh() async {
    if (_refreshing || _isInCall()) return;
    if (!_permissionsGranted) return _startDiscovery();
    _refreshing = true;
    state = state.copyWith(discoveryStatus: DiscoveryStatus.scanning);
    _onDiscoveryResult(await _discoverPeers.refresh());
    _refreshing = false;
  }

  // ── Public Actions ────────────────────────────────────────────────────────

  /// Toggle selection of a peer for a group call.
  void togglePeerSelection(String peerId) {
    final current = Set<String>.from(state.selectedPeerIds);
    if (current.contains(peerId)) {
      current.remove(peerId);
    } else {
      current.add(peerId);
    }
    state = state.copyWith(selectedPeerIds: current);
  }

  /// Initiate a direct 1-to-1 call to [peer].
  Future<void> callPeer(PeerDevice peer) async {
    final granted = await _requestAudioPermission();
    if (!granted) {
      state = state.copyWith(
        errorMessage: 'Microphone permission is required to make calls.',
      );
      return;
    }
    state = state.copyWith(clearError: true);
    final result = await _initiateCall([peer]);
    result.fold(
      onSuccess: (session) {
        _onCallInitiated?.call(session);
      },
      onFailure: (f) => state = state.copyWith(errorMessage: f.message),
    );
  }

  /// Initiate a group call to all currently selected peers.
  Future<void> startGroupCall() async {
    final granted = await _requestAudioPermission();
    if (!granted) {
      state = state.copyWith(
        errorMessage: 'Microphone permission is required to make calls.',
      );
      return;
    }
    final peers = state.peers
        .where((p) => state.selectedPeerIds.contains(p.id))
        .toList();
    if (peers.isEmpty) return;
    state = state.copyWith(clearError: true);
    final result = await _initiateCall(peers);
    result.fold(
      onSuccess: (session) {
        _onCallInitiated?.call(session);
      },
      onFailure: (f) => state = state.copyWith(errorMessage: f.message),
    );
  }

  /// Request Bluetooth discoverability.
  Future<void> makeBtDiscoverable() async {
    const seconds = 120;
    final result = await _makeBtDiscoverable(durationSeconds: seconds);
    result.fold(
      onSuccess: (_) {
        state = state.copyWith(isDiscoverableBt: true);
        // Android turns visibility off by itself after [seconds].
        _visibleTimer?.cancel();
        _visibleTimer = Timer(const Duration(seconds: seconds), () {
          if (mounted) state = state.copyWith(isDiscoverableBt: false);
        });
      },
      onFailure: (f) => state = state.copyWith(errorMessage: f.message),
    );
  }

  void clearError() => state = state.copyWith(clearError: true);

  // ── Private ──────────────────────────────────────────────────────────────

  Future<void> _startDiscovery() async {
    final permissionsGranted = await _requestDiscoveryPermissions();
    if (!permissionsGranted) {
      state = state.copyWith(
        discoveryStatus: DiscoveryStatus.error,
        errorMessage: 'Required permissions were denied. Check app settings.',
      );
      return;
    }

    _permissionsGranted = true;
    state = state.copyWith(discoveryStatus: DiscoveryStatus.scanning);
    _onDiscoveryResult(await _discoverPeers());
  }

  void _onDiscoveryResult(Result<Stream<List<PeerDevice>>> result) {
    if (!mounted) return;
    state = state.copyWith(activeTransports: _discoverPeers.activeTransports);
    result.fold(
      onSuccess: (peerStream) {
        state = state.copyWith(
          discoveryStatus: DiscoveryStatus.active,
          clearError: true,
        );
        _peersSub ??= peerStream.listen((peers) {
          state = state.copyWith(peers: peers);
        });
      },
      onFailure: (f) => state = state.copyWith(
        discoveryStatus: DiscoveryStatus.error,
        errorMessage: f.message,
      ),
    );
  }

  /// Request microphone permission. Returns true if granted.
  Future<bool> _requestAudioPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  /// Request permissions needed for discovery. Returns true if discovery can proceed.
  Future<bool> _requestDiscoveryPermissions() async {
    final results = await [
      Permission.location,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      // Asked up front so incoming calls can be answered right away.
      Permission.microphone,
    ].request();

    final locOk = results[Permission.location]?.isGranted ?? false;
    final btScanOk = results[Permission.bluetoothScan]?.isGranted ?? false;
    final btConnOk = results[Permission.bluetoothConnect]?.isGranted ?? false;

    // Allow discovery if Bluetooth permissions OR Location permissions are granted.
    return locOk || btScanOk || btConnOk || results.values.isEmpty;
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _visibleTimer?.cancel();
    _peersSub?.cancel();
    super.dispose();
  }
}
