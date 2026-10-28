/// Sandbox Riverpod provider overrides.
///
/// Call [sandboxOverrides] when building the [ProviderScope] in
/// [main_sandbox.dart]. This swaps every real data-source and repository
/// with its sandbox fake — zero changes to production providers.dart.
library sandbox_providers;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vocky_call/di/providers.dart';
import 'package:vocky_call/domain/repositories/i_audio_repository.dart';
import 'package:vocky_call/sandbox/fake_audio_repository.dart';
import 'package:vocky_call/sandbox/fake_bt_discovery_source.dart';
import 'package:vocky_call/sandbox/fake_bt_transport_source.dart';
import 'package:vocky_call/sandbox/fake_webrtc_transport_source.dart';
import 'package:vocky_call/sandbox/fake_wifi_discovery_source.dart';

// ── Singleton fake instances (kept alive for the sandbox session) ─────────

/// Singleton WiFi discovery fake — re-used across rebuilds.
final sandboxWifiDiscovery = FakeWifiDiscoverySource();

/// Singleton BT discovery fake — re-used across rebuilds.
final sandboxBtDiscovery = FakeBtDiscoverySource();

/// Singleton WebRTC transport fake — exposes [injectIncomingCall] etc.
final sandboxWebRtcTransport = FakeWebRtcTransportSource();

/// Singleton BT transport fake — exposes [injectIncomingCall] etc.
final sandboxBtTransport = FakeBtTransportSource();

/// Singleton fake audio repository.
final sandboxAudioRepo = FakeAudioRepository();

// ── Provider overrides list ───────────────────────────────────────────────

/// Pass this list to [ProviderScope(overrides: sandboxOverrides)] in
/// `main_sandbox.dart` to replace every production implementation with a fake.
List<Override> get sandboxOverrides => [
      wifiDiscoverySourceProvider.overrideWithValue(sandboxWifiDiscovery),
      btDiscoverySourceProvider.overrideWithValue(sandboxBtDiscovery),
      webRtcTransportSourceProvider
          .overrideWithValue(sandboxWebRtcTransport),
      btTransportSourceProvider.overrideWithValue(sandboxBtTransport),
      audioRepositoryProvider
          .overrideWith((_) => sandboxAudioRepo as IAudioRepository),
    ];
