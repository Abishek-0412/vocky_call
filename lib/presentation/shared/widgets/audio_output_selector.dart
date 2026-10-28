/// AudioOutputSelector — segmented control for earpiece / speaker / walkie.
/// Uses AnimatedContainer for smooth tab-sliding transition.
library audio_output_selector;

import 'package:flutter/material.dart';
import 'package:vocky_call/domain/value_objects/audio_output_mode.dart';
import 'package:vocky_call/presentation/shared/theme/app_colors.dart';
import 'package:vocky_call/presentation/shared/theme/app_typography.dart';

class AudioOutputSelector extends StatelessWidget {
  final AudioOutputMode selected;
  final ValueChanged<AudioOutputMode> onChanged;

  const AudioOutputSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: AudioOutputMode.values.map((mode) {
          final isSelected = selected == mode;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(mode),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      mode.emoji,
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      mode.label,
                      style: AppTypography.labelSmall.copyWith(
                        color: isSelected
                            ? AppColors.background
                            : AppColors.textSecondary,
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
