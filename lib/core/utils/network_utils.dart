import 'dart:io';

class NetworkUtils {
  /// Returns this device's LAN IPv4 address.
  ///
  /// Prefers WiFi / hotspot interfaces (wlan0, swlan0, ap0, eth0, en0) with a
  /// private address, so mobile data (rmnet, ccmni) is never picked.
  static Future<String?> getLocalIp() async =>
      (await getLocalInterface())?.$2.address;

  static Future<(NetworkInterface, InternetAddress)?> getLocalInterface() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      const preferred = ['wlan', 'swlan', 'ap', 'eth', 'en'];
      (NetworkInterface, InternetAddress)? fallback;
      for (final prefix in preferred) {
        for (final iface in interfaces) {
          if (!iface.name.toLowerCase().startsWith(prefix)) continue;
          for (final addr in iface.addresses) {
            if (_isPrivate(addr)) return (iface, addr);
            fallback ??= (iface, addr);
          }
        }
      }
      if (fallback != null) return fallback;
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (_isPrivate(addr)) return (iface, addr);
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static bool _isPrivate(InternetAddress a) {
    final b = a.rawAddress;
    return b[0] == 10 ||
        (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
        (b[0] == 192 && b[1] == 168);
  }
}
