/// Transport type — determines which physical channel is used for a peer.
library transport_type;

enum TransportType {
  wifi,
  bluetooth;

  String get displayName => switch (this) {
        TransportType.wifi => 'WiFi',
        TransportType.bluetooth => 'Bluetooth',
      };

  String get emoji => switch (this) {
        TransportType.wifi => '📶',
        TransportType.bluetooth => '🔵',
      };
}
