/// Sandbox control panel — floating debug overlay.
///
/// Provides one-tap buttons to inject simulated call events into the app
/// without needing a second physical device. Visible only when the app is
/// launched via [main_sandbox.dart].
///
/// Available actions:
///   • Simulate incoming WiFi call
///   • Simulate incoming BT call
///   • Add fake WiFi peer
///   • Add fake BT peer
///   • Simulate call drop (remote hang-up)
library sandbox_control_panel;

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:vocky_call/domain/entities/peer_device.dart';
import 'package:vocky_call/domain/value_objects/transport_type.dart';
import 'package:vocky_call/sandbox/sandbox_providers.dart';

class SandboxControlPanel extends StatefulWidget {
  const SandboxControlPanel({super.key});

  @override
  State<SandboxControlPanel> createState() => _SandboxControlPanelState();
}

class _SandboxControlPanelState extends State<SandboxControlPanel>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    _expanded ? _animController.forward() : _animController.reverse();
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  void _simulateIncomingWifi() {
    sandboxWebRtcTransport.injectIncomingCall(
      callerId: '192.168.1.${Random().nextInt(50) + 100}',
      callerName: 'Sandbox WiFi Caller',
    );
    _showSnack('📶 Incoming WiFi call injected');
  }

  void _simulateIncomingBt() {
    sandboxBtTransport.injectIncomingCall(
      callerId: 'AA:BB:CC:DD:EE:${Random().nextInt(90) + 10}',
      callerName: 'Sandbox BT Caller',
    );
    _showSnack('🔵 Incoming BT call injected');
  }

  void _addFakeWifiPeer() {
    final n = Random().nextInt(900) + 100;
    sandboxWifiDiscovery.injectPeer(PeerDevice(
      id: '10.0.0.$n',
      name: 'Injected WiFi #$n',
      transportType: TransportType.wifi,
      lastSeen: DateTime.now(),
    ));
    _showSnack('➕ WiFi peer added');
  }

  void _addFakeBtPeer() {
    final n = Random().nextInt(90) + 10;
    sandboxBtDiscovery.injectPeer(PeerDevice(
      id: 'FF:EE:DD:CC:BB:$n',
      name: 'Injected BT #$n',
      transportType: TransportType.bluetooth,
      lastSeen: DateTime.now(),
    ));
    _showSnack('➕ BT peer added');
  }

  void _simulateCallDrop() {
    if (sandboxWebRtcTransport.isCallActive) {
      sandboxWebRtcTransport.injectCallEnd();
      _showSnack('📴 WiFi call dropped');
    } else if (sandboxBtTransport.isConnected) {
      sandboxBtTransport.injectCallEnd();
      _showSnack('📴 BT call dropped');
    } else {
      _showSnack('⚠️ No active call to drop');
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'monospace')),
        duration: const Duration(seconds: 2),
        backgroundColor: const Color(0xFF1E293B),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // ── Expandable action buttons ────────────────────────────────────
        FadeTransition(
          opacity: _fadeAnim,
          child: SizeTransition(
            sizeFactor: _fadeAnim,
            axisAlignment: 1,
            child: _expanded
                ? _ActionSheet(
                    onIncomingWifi: _simulateIncomingWifi,
                    onIncomingBt: _simulateIncomingBt,
                    onAddWifiPeer: _addFakeWifiPeer,
                    onAddBtPeer: _addFakeBtPeer,
                    onCallDrop: _simulateCallDrop,
                  )
                : const SizedBox.shrink(),
          ),
        ),
        const SizedBox(height: 8),
        // ── FAB toggle ────────────────────────────────────────────────────
        FloatingActionButton.small(
          heroTag: 'sandbox_fab',
          onPressed: _toggle,
          backgroundColor: const Color(0xFF7C3AED),
          foregroundColor: Colors.white,
          tooltip: 'Sandbox Controls',
          child: AnimatedRotation(
            turns: _expanded ? 0.125 : 0,
            duration: const Duration(milliseconds: 220),
            child: const Icon(Icons.science_rounded),
          ),
        ),
      ],
    );
  }
}

// ── Private action sheet widget ─────────────────────────────────────────────

class _ActionSheet extends StatelessWidget {
  final VoidCallback onIncomingWifi;
  final VoidCallback onIncomingBt;
  final VoidCallback onAddWifiPeer;
  final VoidCallback onAddBtPeer;
  final VoidCallback onCallDrop;

  const _ActionSheet({
    required this.onIncomingWifi,
    required this.onIncomingBt,
    required this.onAddWifiPeer,
    required this.onAddBtPeer,
    required this.onCallDrop,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF7C3AED), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C3AED).withAlpha(77),
            blurRadius: 16,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _label('🧪 Sandbox Controls'),
          const Divider(color: Color(0xFF334155), height: 14),
          _btn('📶 Incoming WiFi Call', const Color(0xFF2563EB),
              onIncomingWifi),
          const SizedBox(height: 6),
          _btn('🔵 Incoming BT Call', const Color(0xFF0891B2), onIncomingBt),
          const SizedBox(height: 6),
          _btn('➕ Add WiFi Peer', const Color(0xFF16A34A), onAddWifiPeer),
          const SizedBox(height: 6),
          _btn('➕ Add BT Peer', const Color(0xFF0D9488), onAddBtPeer),
          const SizedBox(height: 6),
          _btn('📴 Simulate Call Drop', const Color(0xFFDC2626), onCallDrop),
        ],
      ),
    );
  }

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
          color: Color(0xFFE2E8F0),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      );

  Widget _btn(String label, Color color, VoidCallback onTap) =>
      SizedBox(
        height: 34,
        child: ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: color.withAlpha(38),
            foregroundColor: color,
            side: BorderSide(color: color.withAlpha(102)),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            elevation: 0,
          ),
          child: Text(label, overflow: TextOverflow.ellipsis),
        ),
      );
}
