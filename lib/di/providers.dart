/// Dependency injection — ALL Riverpod providers declared here.
///
/// This is the single place where concretions are wired to abstractions.
/// No other file should instantiate repository implementations directly.
library providers;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vocky_call/data/repositories/audio_repository_impl.dart';
import 'package:vocky_call/data/repositories/discovery_repository_impl.dart';
import 'package:vocky_call/data/repositories/transport_repository_impl.dart';
import 'package:vocky_call/data/sources/bluetooth/bt_discovery_source.dart';
import 'package:vocky_call/data/sources/bluetooth/bt_transport_source.dart';
import 'package:vocky_call/data/sources/wifi/webrtc_transport_source.dart';
import 'package:vocky_call/data/sources/wifi/wifi_discovery_source.dart';
import 'package:vocky_call/domain/repositories/i_audio_repository.dart';
import 'package:vocky_call/domain/repositories/i_discovery_repository.dart';
import 'package:vocky_call/domain/repositories/i_transport_repository.dart';
import 'package:vocky_call/domain/use_cases/accept_call_use_case.dart';
import 'package:vocky_call/domain/use_cases/decline_call_use_case.dart';
import 'package:vocky_call/domain/use_cases/discover_peers_use_case.dart';
import 'package:vocky_call/domain/use_cases/end_call_use_case.dart';
import 'package:vocky_call/domain/use_cases/initiate_call_use_case.dart';
import 'package:vocky_call/domain/use_cases/make_bt_discoverable_use_case.dart';
import 'package:vocky_call/domain/use_cases/set_audio_output_use_case.dart';
import 'package:vocky_call/domain/use_cases/toggle_mute_use_case.dart';
import 'package:vocky_call/domain/value_objects/call_state.dart';
import 'package:vocky_call/presentation/features/call/call_controller.dart';
import 'package:vocky_call/presentation/features/home/home_controller.dart';

// ════════════════════════════════════════════════════════════════
// ── Device Name (resolved once, cached)
// ════════════════════════════════════════════════════════════════

/// Provides the human-readable device name (e.g. "moto g64 5G").
/// Must be initialized before the app starts. See main.dart.
final deviceNameProvider = StateProvider<String>((ref) => 'VockyCall Device');

// ════════════════════════════════════════════════════════════════
// ── Data Sources (leaf nodes — no dependencies on other providers)
// ════════════════════════════════════════════════════════════════

final wifiDiscoverySourceProvider = Provider<IWifiDiscoverySource>((ref) {
  final source = WifiDiscoverySource();
  ref.onDispose(source.dispose);
  return source;
});

final btDiscoverySourceProvider = Provider<IBtDiscoverySource>((ref) {
  final source = BtDiscoverySource();
  ref.onDispose(source.dispose);
  return source;
});

final webRtcTransportSourceProvider = Provider<IWebRtcTransportSource>((ref) {
  final source = WebRtcTransportSource();
  ref.onDispose(source.dispose);
  return source;
});

final btTransportSourceProvider = Provider<IBtTransportSource>((ref) {
  final source = BtTransportSource();
  ref.onDispose(source.dispose);
  return source;
});

// ════════════════════════════════════════════════════════════════
// ── Repositories (depend only on source interfaces)
// ════════════════════════════════════════════════════════════════

final discoveryRepositoryProvider = Provider<IDiscoveryRepository>((ref) {
  final btSource = ref.watch(btDiscoverySourceProvider);
  final deviceName = ref.watch(deviceNameProvider);
  final repo = DiscoveryRepositoryImpl(
    sources: [
      ref.watch(wifiDiscoverySourceProvider),
      btSource,
    ],
    localDeviceName: deviceName,
    btSourceForDiscoverability: btSource,
  );
  ref.onDispose(repo.dispose);
  return repo;
});

final transportRepositoryProvider = Provider<ITransportRepository>((ref) {
  final deviceName = ref.watch(deviceNameProvider);
  final repo = TransportRepositoryImpl(
    sources: [
      ref.watch(webRtcTransportSourceProvider),
      ref.watch(btTransportSourceProvider),
    ],
    localDeviceName: deviceName,
  );
  // Initialize transport sources (start signaling server + BT listener).
  repo.initializeSources();
  ref.onDispose(repo.dispose);
  return repo;
});

final audioRepositoryProvider = Provider<IAudioRepository>(
  (_) => AudioRepositoryImpl(),
);

// ════════════════════════════════════════════════════════════════
// ── Use Cases (depend only on repository interfaces)
// ════════════════════════════════════════════════════════════════

final discoverPeersUseCaseProvider = Provider<DiscoverPeersUseCase>(
  (ref) => DiscoverPeersUseCase(ref.watch(discoveryRepositoryProvider)),
);

final initiateCallUseCaseProvider = Provider<InitiateCallUseCase>(
  (ref) => InitiateCallUseCase(
    ref.watch(transportRepositoryProvider),
    ref.watch(audioRepositoryProvider),
  ),
);

final acceptCallUseCaseProvider = Provider<AcceptCallUseCase>(
  (ref) => AcceptCallUseCase(
    ref.watch(transportRepositoryProvider),
    ref.watch(audioRepositoryProvider),
  ),
);

final declineCallUseCaseProvider = Provider<DeclineCallUseCase>(
  (ref) => DeclineCallUseCase(ref.watch(transportRepositoryProvider)),
);

final endCallUseCaseProvider = Provider<EndCallUseCase>(
  (ref) => EndCallUseCase(
    ref.watch(transportRepositoryProvider),
    ref.watch(audioRepositoryProvider),
  ),
);

final toggleMuteUseCaseProvider = Provider<ToggleMuteUseCase>(
  (ref) => ToggleMuteUseCase(ref.watch(audioRepositoryProvider)),
);

final setAudioOutputUseCaseProvider = Provider<SetAudioOutputUseCase>(
  (ref) => SetAudioOutputUseCase(ref.watch(audioRepositoryProvider)),
);

final makeBtDiscoverableUseCaseProvider = Provider<MakeBtDiscoverableUseCase>(
  (ref) => MakeBtDiscoverableUseCase(ref.watch(discoveryRepositoryProvider)),
);

// ════════════════════════════════════════════════════════════════
// ── Controllers / StateNotifiers (single source of truth for UI state)
// ════════════════════════════════════════════════════════════════

final callControllerProvider =
    StateNotifierProvider<CallController, CallUiState>((ref) {
  return CallController(
    acceptCall: ref.watch(acceptCallUseCaseProvider),
    declineCall: ref.watch(declineCallUseCaseProvider),
    endCall: ref.watch(endCallUseCaseProvider),
    toggleMute: ref.watch(toggleMuteUseCaseProvider),
    setAudioOutput: ref.watch(setAudioOutputUseCaseProvider),
    transportRepo: ref.watch(transportRepositoryProvider),
  );
});

final homeControllerProvider =
    StateNotifierProvider<HomeController, HomeState>((ref) {
  final callCtrl = ref.read(callControllerProvider.notifier);
  return HomeController(
    discoverPeers: ref.watch(discoverPeersUseCaseProvider),
    initiateCall: ref.watch(initiateCallUseCaseProvider),
    makeBtDiscoverable: ref.watch(makeBtDiscoverableUseCaseProvider),
    onCallInitiated: (session) {
      callCtrl.onCallInitiated(
        session.sessionId,
        session.participantIds,
        participantNames: session.participantNames,
      );
    },
    isInCall: () {
      final callState = ref.read(callControllerProvider).callState;
      return callState is! CallIdle && callState is! CallEnded;
    },
  );
});
