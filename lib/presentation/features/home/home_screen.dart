/// HomeScreen — peer list with discovery status and call/group-call controls.
///
/// Rules:
///  - NO business logic here. Read state from HomeController, dispatch actions.
///  - NO local setState. All state comes from Riverpod.
///  - Incoming call sheet is shown as a modal overlay without pushing a route.
library home_screen;


import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vocky_call/di/providers.dart';
import 'package:vocky_call/domain/value_objects/call_state.dart';
import 'package:vocky_call/domain/value_objects/transport_type.dart';
import 'package:vocky_call/presentation/features/home/home_controller.dart';
import 'package:vocky_call/presentation/features/home/home_state.dart';
import 'package:vocky_call/presentation/shared/theme/app_colors.dart';
import 'package:vocky_call/presentation/shared/theme/app_spacing.dart';
import 'package:vocky_call/presentation/shared/theme/app_typography.dart';
import 'package:vocky_call/presentation/shared/widgets/incoming_call_sheet.dart';
import 'package:vocky_call/presentation/shared/widgets/peer_card.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _sheetShown = false;
  BuildContext? _sheetContext;

  @override
  Widget build(BuildContext context) {
    final homeState = ref.watch(homeControllerProvider);
    final homeCtrl = ref.read(homeControllerProvider.notifier);
    final deviceName = ref.watch(deviceNameProvider);
    final callCtrl = ref.read(callControllerProvider.notifier);

    // Use ref.listen instead of addPostFrameCallback to prevent duplicate
    // callback registration on every rebuild.
    ref.listen<CallState>(
      callControllerProvider.select((s) => s.callState),
      (prev, next) {
        if (next is CallRinging && !_sheetShown) {
          _sheetShown = true;
          _showIncomingSheet(context, next, callCtrl);
        }
        if (next is CallActive) {
          _sheetShown = false;
          if (context.mounted) context.go('/call');
        }
        if (next is CallIdle || next is CallEnded) {
          _sheetShown = false;
          // Caller hung up before we answered — close the incoming sheet.
          final sheet = _sheetContext;
          if (sheet != null && sheet.mounted) Navigator.pop(sheet);
        }
      },
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(homeState, homeCtrl, deviceName),
      body: Column(
        children: [
          // Status bar
          _DiscoveryBanner(
            status: homeState.discoveryStatus,
            transports: homeState.activeTransports,
          ),

          // Error snackbar
          if (homeState.errorMessage != null)
            _ErrorBanner(
              message: homeState.errorMessage!,
              onDismiss: homeCtrl.clearError,
            ),

          // Peer list
          Expanded(
            child: homeState.peers.isEmpty
                ? _EmptyState(status: homeState.discoveryStatus)
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                    itemCount: homeState.peers.length,
                    itemBuilder: (_, i) {
                      final peer = homeState.peers[i];
                      return PeerCard(
                        peer: peer,
                        isSelected:
                            homeState.selectedPeerIds.contains(peer.id),
                        onCall: () => homeCtrl.callPeer(peer),
                        onToggleSelect: () =>
                            homeCtrl.togglePeerSelection(peer.id),
                      );
                    },
                  ),
          ),

          // Group call button (only when 2+ selected)
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            child: homeState.hasSelection
                ? _GroupCallBar(
                    count: homeState.selectedPeerIds.length,
                    enabled: homeState.canStartGroupCall,
                    onTap: homeCtrl.startGroupCall,
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  AppBar _buildAppBar(HomeState state, HomeController ctrl, String deviceName) {
    return AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('VockyCall', style: AppTypography.titleLarge),
          Text(
            'This device: $deviceName',
            style: AppTypography.bodyMedium,
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: ctrl.refresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
        Padding(
          padding: const EdgeInsets.only(right: AppSpacing.md),
          child: TextButton.icon(
            onPressed: ctrl.makeBtDiscoverable,
            icon: const Icon(Icons.bluetooth_searching_rounded, size: 16),
            label: Text(
              state.isDiscoverableBt ? 'Visible' : 'Make Visible',
              style: AppTypography.labelSmall,
            ),
            style: TextButton.styleFrom(
              foregroundColor: state.isDiscoverableBt
                  ? AppColors.primary
                  : AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  void _showIncomingSheet(
    BuildContext context,
    CallRinging ringing,
    callCtrl,
  ) {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        _sheetContext = sheetContext;
        return IncomingCallSheet(
          callerName: ringing.callerName,
          transportLabel: ringing.transportLabel,
          onAnswer: () {
            Navigator.pop(sheetContext);
            callCtrl.answerCall(ringing.callerId);
          },
          onDecline: () {
            Navigator.pop(sheetContext);
            callCtrl.declineCall(ringing.callerId);
            _sheetShown = false;
          },
        );
      },
    ).whenComplete(() {
      _sheetShown = false;
      _sheetContext = null;
    });
  }
}

// ── Sub-widgets ──────────────────────────────────────────────────────────────

class _DiscoveryBanner extends StatelessWidget {
  final DiscoveryStatus status;
  final Set<TransportType> transports;
  const _DiscoveryBanner({required this.status, required this.transports});

  @override
  Widget build(BuildContext context) {
    final wifi = transports.contains(TransportType.wifi);
    final bt = transports.contains(TransportType.bluetooth);
    final via = wifi && bt
        ? 'WiFi + Bluetooth'
        : wifi
            ? 'WiFi only (Bluetooth off)'
            : 'Bluetooth only (no WiFi)';
    final (color, text, showSpinner) = switch (status) {
      DiscoveryStatus.idle => (AppColors.textMuted, 'Starting...', false),
      DiscoveryStatus.scanning => (AppColors.primary, 'Scanning for nearby devices...', true),
      DiscoveryStatus.active => (AppColors.callGreen, 'Listening on $via', false),
      DiscoveryStatus.error => (AppColors.callRed, 'Discovery error', false),
    };

    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          if (showSpinner)
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: color,
              ),
            )
          else
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          const SizedBox(width: AppSpacing.sm),
          Text(text, style: AppTypography.bodyMedium.copyWith(color: color)),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;
  const _ErrorBanner({required this.message, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(AppSpacing.md),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.callRed.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.callRed.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AppColors.callRed, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: AppTypography.bodyMedium.copyWith(color: AppColors.callRed),
            ),
          ),
          GestureDetector(
            onTap: onDismiss,
            child: const Icon(Icons.close, color: AppColors.callRed, size: 16),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final DiscoveryStatus status;
  const _EmptyState({required this.status});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            status == DiscoveryStatus.error
                ? Icons.wifi_off_rounded
                : Icons.devices_rounded,
            size: 56,
            color: AppColors.textMuted,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            status == DiscoveryStatus.error
                ? 'Discovery failed'
                : 'No devices found yet',
            style: AppTypography.titleMedium.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 6),
          Text(
            status == DiscoveryStatus.error
                ? 'Turn on Bluetooth or connect to WiFi,\nthen tap refresh'
                : 'Make sure other devices have VockyCall open\non the same WiFi or enable Bluetooth.\nRefreshing every 20 seconds.',
            style: AppTypography.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _GroupCallBar extends StatelessWidget {
  final int count;
  final bool enabled;
  final VoidCallback onTap;

  const _GroupCallBar({
    required this.count,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.md + MediaQuery.of(context).padding.bottom,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: ElevatedButton.icon(
        onPressed: enabled ? onTap : null,
        icon: const Icon(Icons.group_rounded, size: 18),
        label: Text(
          count < 2
              ? 'Select one more to start group call'
              : 'Start Group Call ($count devices)',
        ),
      ),
    );
  }
}
