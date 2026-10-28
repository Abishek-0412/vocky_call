/// Sandbox entry point.
///
/// Run with:
///   flutter run -t lib/main_sandbox.dart
///
/// This boots the full VockyCallApp but with all real data-sources
/// (WiFi, Bluetooth, WebRTC, Audio) replaced by in-process fakes.
/// A floating [SandboxControlPanel] overlay is mounted on top so you can
/// inject call events without needing a second physical device.
library main_sandbox;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vocky_call/app.dart';
import 'package:vocky_call/sandbox/sandbox_control_panel.dart';
import 'package:vocky_call/sandbox/sandbox_providers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  runApp(
    ProviderScope(
      // Swap every real implementation with a sandbox fake.
      overrides: sandboxOverrides,
      child: const _SandboxRoot(),
    ),
  );
}

/// Wraps [VockyCallApp] with the floating sandbox control panel overlay.
class _SandboxRoot extends StatelessWidget {
  const _SandboxRoot();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const VockyCallApp(),
        const Positioned(
          bottom: 24,
          right: 16,
          child: SandboxControlPanel(),
        ),
      ],
    );
  }
}
