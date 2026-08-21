import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Shared background for secondary operational pages.
class LiquidPageBackdrop extends StatelessWidget {
  const LiquidPageBackdrop({
    this.startColor = const Color(0xFFF3F7FB),
    this.endColor = const Color(0xFFDCE6F1),
    super.key,
  });

  final Color startColor;
  final Color endColor;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [startColor, endColor],
      ),
    ),
    child: const CustomPaint(painter: _GridPainter()),
  );
}

class _GridPainter extends CustomPainter {
  const _GridPainter();

  static const double spacing = 48;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.navy.withValues(alpha: .035)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Consistent back navigation header used outside the main map.
class NavyPageHeader extends StatelessWidget {
  const NavyPageHeader({required this.title, this.trailing, super.key});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => ClipRect(
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
      child: Container(
        height: 74,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        decoration: BoxDecoration(
          color: AppColors.navy.withValues(alpha: .95),
          border: Border(
            bottom: BorderSide(color: Colors.white.withValues(alpha: .18)),
          ),
        ),
        child: Row(
          children: [
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back_rounded),
              color: Colors.white,
              tooltip: '관제로 돌아가기',
            ),
            const SizedBox(width: 10),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (trailing != null) ...[const Spacer(), trailing!],
          ],
        ),
      ),
    ),
  );
}

/// Shared translucent surface for secondary-page content.
class LiquidGlassPanel extends StatelessWidget {
  const LiquidGlassPanel({
    required this.child,
    this.width,
    this.padding,
    super.key,
  });

  final Widget child;
  final double? width;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(22),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
      child: Container(
        width: width,
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .84),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: .94)),
          boxShadow: [
            BoxShadow(
              color: AppColors.navy.withValues(alpha: .09),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: child,
      ),
    ),
  );
}
