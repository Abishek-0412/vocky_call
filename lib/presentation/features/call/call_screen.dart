/// CallScreen — active call UI with participants, audio controls, and timer.
///
/// Rules:
///  - Pure UI — reads CallUiState, dispatches to CallController.
///  - Uses AnimatedSwitcher for smooth state transitions.
///  - No local setState.
library call_screen;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vocky_call/di/providers.dart';
import 'package:vocky_call/domain/value_objects/audio_output_mode.dart';
import 'package:vocky_call/domain/value_objects/call_state.dart';
import 'package:vocky_call/presentation/features/call/call_controller.dart';
import 'package:vocky_call/presentation/features/call/call_ui_state.dart';
import 'package:vocky_call/presentation/shared/theme/app_colors.dart';
import 'package:vocky_call/presentation/shared/theme/app_spacing.dart';
import 'package:vocky_call/presentation/shared/theme/app_typography.dart';
import 'package:vocky_call/presentation/shared/widgets/audio_output_selector.dart';
import 'package:vocky_call/presentation/shared/widgets/waveform_indicator.dart';

class CallScreen extends ConsumerWidget {
  const CallScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(callControllerProvider);
    final ctrl = ref.read(callControllerProvider.notifier);

    // Auto-navigate back when call ends
    ref.listen<CallUiState>(callControllerProvider, (_, next) {
      if (next.callState is CallIdle && context.mounted) {
        context.go('/');
      }
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: switch (state.callState) {
          CallActive active => _ActiveCallBody(
              state: state,
              participantIds: active.participantIds,
              participantNames: active.participantNames,
              connected: active.connected,
              ctrl: ctrl,
            ),
          CallEnded _ => const _EndedBody(),
          _ => const SizedBox.shrink(),
        },
      ),
    );
  }
}

// ── Active Call ──────────────────────────────────────────────────────────────

class _ActiveCallBody extends StatelessWidget {
  final CallUiState state;
  final List<String> participantIds;
  final Map<String, String> participantNames;
  final bool connected;
  final CallController ctrl;

  const _ActiveCallBody({
    required this.state,
    required this.participantIds,
    required this.participantNames,
    required this.connected,
    required this.ctrl,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 0,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      participantIds.length == 1
                          ? '1 Person'
                          : '${participantIds.length} People',
                      style: AppTypography.bodyMedium,
                    ),
                    Text(
                      connected ? 'Active Call' : 'Calling…',
                      style: AppTypography.titleLarge,
                    ),
                  ],
                ),
              ),
              // Timer (starts when the other side answers)
              if (connected) _ElapsedTimer(elapsed: state.elapsed),
            ],
          ),
        ),

        const SizedBox(height: AppSpacing.xl),

        // Participant cards
        Expanded(
          child: participantIds.isEmpty
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  child: _ParticipantGrid(
                    participantIds: participantIds,
                    participantNames: participantNames,
                    speakingMap: state.speakingMap,
                  ),
                ),
        ),

        const SizedBox(height: AppSpacing.lg),

        // Audio output selector
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text('Audio Output', style: AppTypography.bodyMedium),
              ),
              AudioOutputSelector(
                selected: state.audioSettings.outputMode,
                onChanged: ctrl.setAudioOutput,
              ),
            ],
          ),
        ),

        const SizedBox(height: AppSpacing.lg),

        // Controls row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: state.audioSettings.outputMode == AudioOutputMode.walkieTalkie
              ? _WalkieTalkieControls(
                  isPttActive: state.audioSettings.isPttPressed,
                  onPttPress: ctrl.onPttPressed,
                  onPttRelease: ctrl.onPttReleased,
                  onEnd: ctrl.endCall,
                )
              : _StandardControls(
                  isMuted: state.audioSettings.isMuted,
                  onMute: ctrl.toggleMute,
                  onEnd: ctrl.endCall,
                ),
        ),

        SizedBox(height: AppSpacing.lg + MediaQuery.of(context).padding.bottom),
      ],
    );
  }
}

class _ElapsedTimer extends StatelessWidget {
  final Duration elapsed;
  const _ElapsedTimer({required this.elapsed});

  String _format(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.circle, size: 8, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(_format(elapsed), style: AppTypography.mono),
        ],
      ),
    );
  }
}

class _ParticipantGrid extends StatelessWidget {
  final List<String> participantIds;
  final Map<String, String> participantNames;
  final Map<String, bool> speakingMap;

  const _ParticipantGrid({
    required this.participantIds,
    required this.participantNames,
    required this.speakingMap,
  });

  String _name(String id) {
    final name = participantNames[id];
    return name == null || name.isEmpty ? id : name;
  }

  @override
  Widget build(BuildContext context) {
    // Single peer: full-width card
    if (participantIds.length == 1) {
      return _ParticipantCard(
        name: _name(participantIds.first),
        isSpeaking: speakingMap[participantIds.first] ?? false,
        large: true,
      );
    }
    // Multiple peers: grid
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.1,
      ),
      itemCount: participantIds.length,
      itemBuilder: (_, i) => _ParticipantCard(
        name: _name(participantIds[i]),
        isSpeaking: speakingMap[participantIds[i]] ?? false,
        large: false,
      ),
    );
  }
}

class _ParticipantCard extends StatelessWidget {
  final String name;
  final bool isSpeaking;
  final bool large;

  const _ParticipantCard({
    required this.name,
    required this.isSpeaking,
    required this.large,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isSpeaking
              ? AppColors.primary.withValues(alpha: 0.6)
              : AppColors.border,
          width: isSpeaking ? 2 : 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: large ? 64 : 48,
            height: large ? 64 : 48,
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSpeaking
                    ? AppColors.primary.withValues(alpha: 0.4)
                    : Colors.transparent,
                width: 2,
              ),
            ),
            child: Icon(
              Icons.smartphone_rounded,
              color: isSpeaking ? AppColors.primary : AppColors.textSecondary,
              size: large ? 32 : 24,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            name,
            textAlign: TextAlign.center,
            style: large ? AppTypography.titleMedium : AppTypography.bodyMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          WaveformIndicator(active: isSpeaking, height: 18),
        ],
      ),
    );
  }
}

class _StandardControls extends StatelessWidget {
  final bool isMuted;
  final VoidCallback onMute;
  final VoidCallback onEnd;

  const _StandardControls({
    required this.isMuted,
    required this.onMute,
    required this.onEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Mute toggle
        Expanded(
          child: _ControlButton(
            icon: isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
            label: isMuted ? 'Unmute' : 'Mute',
            color: isMuted ? AppColors.callRed : AppColors.textSecondary,
            onTap: onMute,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        // End call
        Expanded(
          flex: 2,
          child: GestureDetector(
            onTap: onEnd,
            child: Container(
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.callRed,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.call_end_rounded,
                      color: Colors.white, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'End Call',
                    style: AppTypography.titleMedium
                        .copyWith(color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _WalkieTalkieControls extends StatelessWidget {
  final bool isPttActive;
  final VoidCallback onPttPress;
  final VoidCallback onPttRelease;
  final VoidCallback onEnd;

  const _WalkieTalkieControls({
    required this.isPttActive,
    required this.onPttPress,
    required this.onPttRelease,
    required this.onEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // PTT button
        GestureDetector(
          onTapDown: (_) => onPttPress(),
          onTapUp: (_) => onPttRelease(),
          onTapCancel: onPttRelease,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            height: 72,
            decoration: BoxDecoration(
              color: isPttActive
                  ? AppColors.primary
                  : AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: isPttActive ? 1 : 0.4),
                width: 2,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.mic_rounded,
                  color: isPttActive ? Colors.black : AppColors.primary,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  isPttActive ? 'Speaking...' : 'Hold to Talk',
                  style: AppTypography.titleMedium.copyWith(
                    color: isPttActive ? Colors.black : AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        // End call
        GestureDetector(
          onTap: onEnd,
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.callRed.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.callRed.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.call_end_rounded,
                    color: AppColors.callRed, size: 20),
                const SizedBox(width: 8),
                Text(
                  'End Call',
                  style: AppTypography.titleMedium
                      .copyWith(color: AppColors.callRed),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 3),
            Text(
              label,
              style: AppTypography.labelSmall.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Ended State ──────────────────────────────────────────────────────────────

class _EndedBody extends StatelessWidget {
  const _EndedBody();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.call_end_rounded, color: AppColors.callRed, size: 48),
          SizedBox(height: 16),
          Text('Call Ended', style: TextStyle(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
