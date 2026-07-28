import 'package:flutter/material.dart';

/// Design token source of truth — Mission Control design system.
/// Palette follows KRDS (Korea government Design System) tokens, the same
/// system mnd.go.kr is built on — chosen so a 관제 app used alongside
/// military/government operations reads as institutional, not a generic
/// SaaS dashboard. Light theme only; dark mode and outdoor high-contrast
/// mode are out of scope for this project.
class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF0B50D0); // KRDS primary-60
  static const Color primaryInk = Color(0xFFFFFFFF);

  /// Deep navy identity color (KRDS secondary-80) — app bars and other
  /// authority-bearing chrome, distinct from [primary]'s interactive blue.
  static const Color navy = Color(0xFF052B57);

  static const Color background = Color(0xFFF4F5F6); // KRDS gray-5
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceSunken = Color(0xFFEEF2F7); // KRDS secondary-5
  static const Color border = Color(0xFFCDD1D5); // KRDS gray-20

  static const Color textPrimary = Color(0xFF1E2124); // KRDS gray-90
  static const Color textSecondary = Color(0xFF6D7882); // KRDS gray-50

  static const Color success = Color(0xFF228738); // KRDS success-50
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFDE3412); // KRDS danger-50
  static const Color info = primary;
  static const Color offline = Color(0xFF8A949E); // KRDS gray-40
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
