import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';

/// Returns a human-readable device name.
///
/// On Android, uses the device model name (e.g. "moto g64 5G").
/// Falls back to [Platform.localHostname] on other platforms.
class DeviceNameUtil {
  static String? _cachedName;

  static Future<String> getDeviceName() async {
    if (_cachedName != null) return _cachedName!;

    try {
      if (Platform.isAndroid) {
        final info = await DeviceInfoPlugin().androidInfo;
        // Use model name, e.g. "moto g64 5G", "Samsung Galaxy S24"
        _cachedName = info.model;
      } else if (Platform.isIOS) {
        final info = await DeviceInfoPlugin().iosInfo;
        _cachedName = info.name;
      }
    } catch (_) {
      // Fallback
    }

    _cachedName ??= Platform.localHostname;
    // Guard against "localhost" which is useless
    if (_cachedName == 'localhost' || _cachedName!.isEmpty) {
      _cachedName = 'VockyCall Device';
    }
    return _cachedName!;
  }
}
