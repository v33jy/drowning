import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Shared status vocabulary used across drone cards, detection log,
/// notification timeline, and the drone table view.
enum Severity { ok, warning, danger, offline }

extension SeverityColorX on Severity {
  Color resolve(BuildContext context) {
    final colors = Theme.of(context).extension<AppSemanticColors>()!;
    return switch (this) {
      Severity.ok => colors.success,
      Severity.warning => colors.warning,
      Severity.danger => colors.danger,
      Severity.offline => colors.offline,
    };
  }
}

/// Small filled circle indicating severity. Always paired with a text label
/// elsewhere (see [StatusChip]) — color alone never carries the meaning.
class SeverityDot extends StatelessWidget {
  const SeverityDot({super.key, required this.severity, this.size = 6});

  final Severity severity;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: severity.resolve(context),
        shape: BoxShape.circle,
      ),
    );
  }
}

/// Vertical color stripe for list rows (detection log, notification center).
/// Place inside a [Row] with `crossAxisAlignment: CrossAxisAlignment.stretch`
/// so it fills the row's height.
class SeverityStripe extends StatelessWidget {
  const SeverityStripe({super.key, required this.severity, this.width = 3});

  final Severity severity;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: severity.resolve(context),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}
