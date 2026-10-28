/// IncomingCallSheet — bottom sheet shown when a call arrives.
/// Displayed as a modal over HomeScreen — no navigation needed.
library incoming_call_sheet;

import 'package:flutter/material.dart';
import 'package:vocky_call/presentation/shared/theme/app_colors.dart';
import 'package:vocky_call/presentation/shared/theme/app_spacing.dart';
import 'package:vocky_call/presentation/shared/theme/app_typography.dart';

class IncomingCallSheet extends StatelessWidget {
  final String callerName;
  final String transportLabel;
  final VoidCallback onAnswer;
  final VoidCallback onDecline;

  const IncomingCallSheet({
    super.key,
    required this.callerName,
    required this.transportLabel,
    required this.onAnswer,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg + MediaQuery.of(context).padding.bottom,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Caller avatar
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.3), width: 2),
            ),
            child: const Icon(
              Icons.smartphone_rounded,
              color: AppColors.primary,
              size: 36,
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          Text('Incoming Call', style: AppTypography.bodyMedium),
          const SizedBox(height: 4),
          Text(callerName, style: AppTypography.displayMedium),
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                transportLabel == 'WiFi' ? Icons.wifi_rounded : Icons.bluetooth_rounded,
                size: 14,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 4),
              Text('via $transportLabel', style: AppTypography.bodyMedium),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),

          // Buttons
          Row(
            children: [
              // Decline
              Expanded(
                child: _ActionButton(
                  icon: Icons.call_end_rounded,
                  label: 'Decline',
                  color: AppColors.callRed,
                  onTap: onDecline,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              // Answer
              Expanded(
                child: _ActionButton(
                  icon: Icons.call_rounded,
                  label: 'Answer',
                  color: AppColors.callGreen,
                  onTap: onAnswer,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
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
        height: 64,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 8),
            Text(
              label,
              style: AppTypography.titleMedium.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}
