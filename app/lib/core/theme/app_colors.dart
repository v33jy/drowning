import 'package:flutter/material.dart';

/// Design token source of truth — Mission Control design system.
/// Light theme only; dark mode and outdoor high-contrast mode are out of
/// scope for this project.
class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF1D4ED8);
  static const Color primaryInk = Color(0xFFFFFFFF);

  static const Color background = Color(0xFFF8FAFC);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceSunken = Color(0xFFF1F5F9);
  static const Color border = Color(0xFFE2E8F0);

  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF64748B);

  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFDC2626);
  static const Color info = primary;
  static const Color offline = Color(0xFF6B7280);
}

/// Semantic status colors that Material 3's [ColorScheme] has no native slot
/// for (success/warning/offline — only [ColorScheme.error] is built in).
/// Access via `Theme.of(context).extension<AppSemanticColors>()!`.
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.success,
    required this.warning,
    required this.danger,
    required this.offline,
  });

  final Color success;
  final Color warning;
  final Color danger;
  final Color offline;

  static const standard = AppSemanticColors(
    success: AppColors.success,
    warning: AppColors.warning,
    danger: AppColors.danger,
    offline: AppColors.offline,
  );

  @override
  AppSemanticColors copyWith({
    Color? success,
    Color? warning,
    Color? danger,
    Color? offline,
  }) {
    return AppSemanticColors(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      offline: offline ?? this.offline,
    );
  }

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) {
    if (other is! AppSemanticColors) return this;
    return AppSemanticColors(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      offline: Color.lerp(offline, other.offline, t)!,
    );
  }
}
