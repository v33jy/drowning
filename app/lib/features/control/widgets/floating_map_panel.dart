import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

class FloatingMapPanel extends StatelessWidget {
  const FloatingMapPanel({
    required this.maxHeight,
    required this.child,
    this.onResize,
    super.key,
  });

  final double maxHeight;
  final Widget child;
  final ValueChanged<DragUpdateDetails>? onResize;

  @override
  Widget build(BuildContext context) {
    final panel = ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F7FB),
              border: Border.all(color: Colors.white.withValues(alpha: 0.92)),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.55),
                  blurRadius: 1,
                  offset: const Offset(0, 1),
                ),
                BoxShadow(
                  color: AppColors.navy.withValues(alpha: 0.18),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );

    if (onResize == null) return panel;

    return Stack(
      children: [
        panel,
        Positioned(
          left: 2,
          bottom: 2,
          child: Tooltip(
            message: '크기 조절',
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeUpLeftDownRight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: onResize,
                child: const SizedBox(
                  width: 28,
                  height: 28,
                  child: Icon(
                    Icons.south_west_rounded,
                    size: 15,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
