import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vocky_call/core/utils/device_name_util.dart';
import 'package:vocky_call/di/providers.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock orientation to portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Transparent status bar
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  // Resolve real device name (e.g. "moto g64 5G") before providers initialize.
  final deviceName = await DeviceNameUtil.getDeviceName();

  runApp(
    // ProviderScope is the root of the Riverpod DI tree
    ProviderScope(
      overrides: [
        deviceNameProvider.overrideWith((_) => deviceName),
      ],
      child: const VockyCallApp(),
    ),
  );
}
