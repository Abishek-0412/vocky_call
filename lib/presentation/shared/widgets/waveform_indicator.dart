/// WaveformIndicator — simple animated bars showing audio activity.
/// Uses a subtle pulsing effect. No heavy computation.
library waveform_indicator;

import 'package:flutter/material.dart';
import 'package:vocky_call/presentation/shared/theme/app_colors.dart';

class WaveformIndicator extends StatefulWidget {
  final bool active;
  final Color color;
  final double height;

  const WaveformIndicator({
    super.key,
    required this.active,
    this.color = AppColors.speaking,
    this.height = 24,
  });

  @override
  State<WaveformIndicator> createState() => _WaveformIndicatorState();
}

class _WaveformIndicatorState extends State<WaveformIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<Animation<double>> _barAnimations;

  static const _barCount = 4;
  static const _delays = [0.0, 0.2, 0.4, 0.6];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _barAnimations = List.generate(_barCount, (i) {
      return Tween<double>(begin: 0.2, end: 1.0).animate(
        CurvedAnimation(
          parent: _controller,
          curve: Interval(_delays[i], (_delays[i] + 0.4).clamp(0.0, 1.0),
              curve: Curves.easeInOut),
        ),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) {
      return SizedBox(
        height: widget.height,
        width: _barCount * 6.0 + (_barCount - 1) * 3.0,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(
            _barCount,
            (_) => Container(
              width: 4,
              height: widget.height * 0.2,
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              decoration: BoxDecoration(
                color: AppColors.textMuted,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: widget.height,
      width: _barCount * 6.0 + (_barCount - 1) * 3.0,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, __) => Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(_barCount, (i) {
            return Container(
              width: 4,
              height: widget.height * _barAnimations[i].value,
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        ),
      ),
    );
  }
}
