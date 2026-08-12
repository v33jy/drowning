import 'package:flutter/material.dart';

/// Compact top-view quadcopter glyph for map markers.
class DroneIcon extends StatelessWidget {
  const DroneIcon({required this.color, this.size = 28, super.key});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _DroneIconPainter(color));
}

class _DroneIconPainter extends CustomPainter {
  const _DroneIconPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 28;
    final center = Offset(size.width / 2, size.height / 2);
    final stroke = Paint()
      ..color = color
      ..strokeWidth = 2.2 * scale
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    const directions = [
      Offset(-1, -1),
      Offset(1, -1),
      Offset(-1, 1),
      Offset(1, 1),
    ];
    for (final direction in directions) {
      final rotor = center + direction * (8.5 * scale);
      canvas.drawLine(center, rotor, stroke);
      canvas.drawCircle(rotor, 3.8 * scale, stroke);
    }

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: 8 * scale, height: 10 * scale),
        Radius.circular(3 * scale),
      ),
      fill,
    );
    canvas.drawCircle(
      center + Offset(0, 2.2 * scale),
      1.2 * scale,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_DroneIconPainter oldDelegate) =>
      oldDelegate.color != color;
}
