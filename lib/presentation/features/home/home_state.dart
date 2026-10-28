/// HomeState — immutable state for the home screen.
/// Single source of truth for peer discovery and selection.
library home_state;

import 'package:vocky_call/domain/entities/peer_device.dart';
import 'package:vocky_call/domain/value_objects/transport_type.dart';

enum DiscoveryStatus { idle, scanning, active, error }

final class HomeState {
  final List<PeerDevice> peers;
  final DiscoveryStatus discoveryStatus;
  final Set<String> selectedPeerIds;
  final String? errorMessage;
  final bool isDiscoverableBt;

  /// Transports discovery is running on (WiFi, Bluetooth or both).
  final Set<TransportType> activeTransports;

  const HomeState({
    this.peers = const [],
    this.discoveryStatus = DiscoveryStatus.idle,
    this.selectedPeerIds = const {},
    this.errorMessage,
    this.isDiscoverableBt = false,
    this.activeTransports = const {},
  });

  const HomeState.initial() : this();

  HomeState copyWith({
    List<PeerDevice>? peers,
    DiscoveryStatus? discoveryStatus,
    Set<String>? selectedPeerIds,
    String? errorMessage,
    bool clearError = false,
    bool? isDiscoverableBt,
    Set<TransportType>? activeTransports,
  }) {
    return HomeState(
      peers: peers ?? this.peers,
      discoveryStatus: discoveryStatus ?? this.discoveryStatus,
      selectedPeerIds: selectedPeerIds ?? this.selectedPeerIds,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      isDiscoverableBt: isDiscoverableBt ?? this.isDiscoverableBt,
      activeTransports: activeTransports ?? this.activeTransports,
    );
  }

  bool get canStartGroupCall => selectedPeerIds.length >= 2;
  bool get hasSelection => selectedPeerIds.isNotEmpty;
}
