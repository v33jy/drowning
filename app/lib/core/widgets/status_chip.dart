import 'package:flutter/material.dart';

import 'severity.dart';

/// Dot + label pill — the only approved way to show a status in this app.
/// Never render a bare colored dot/box without this label next to it.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.severity, required this.label});

  final Severity severity;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = severity.resolve(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SeverityDot(severity: severity),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
