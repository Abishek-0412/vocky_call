/// TransportBadge — small chip showing WiFi or BT transport.
library transport_badge;

import 'package:flutter/material.dart';
import 'package:vocky_call/domain/value_objects/transport_type.dart';
import 'package:vocky_call/presentation/shared/theme/app_colors.dart';
import 'package:vocky_call/presentation/shared/theme/app_typography.dart';

class TransportBadge extends StatelessWidget {
  final TransportType type;
  const TransportBadge({super.key, required this.type});

  @override
  Widget build(BuildContext context) {
    final color = type == TransportType.wifi ? AppColors.wifiBlue : AppColors.btBlue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            type == TransportType.wifi ? Icons.wifi_rounded : Icons.bluetooth_rounded,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            type.displayName,
            style: AppTypography.labelSmall.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
