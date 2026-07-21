import 'package:flutter/material.dart';

/// Typography — single sans family, Bold titles / Regular body only.
///
/// The design system calls for Pretendard. No font asset is bundled here —
/// [fontFamily] is left `null` so the platform default is used
/// (San Francisco on iOS, Roboto/Noto Sans CJK on Android), which reads very
/// close to Pretendard for Korean text. To switch to the real Pretendard
/// font once the .otf files are available: drop them under
/// `assets/fonts/`, register a `fonts:` block in pubspec.yaml, and set
/// [fontFamily] to that family name — every TextStyle below picks it up
/// automatically through [TextTheme.apply].
class AppTypography {
  AppTypography._();

  static const String? fontFamily = null;

  static TextTheme textTheme(Color textPrimary, Color textSecondary) {
    return TextTheme(
      // Display — screen-level headings.
      displaySmall: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: textPrimary,
        height: 1.25,
      ),
      // Title — section/dialog/sheet headers.
      titleLarge: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: textPrimary,
        height: 1.3,
      ),
      titleMedium: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: textPrimary,
        height: 1.3,
      ),
      // Body — regular content text.
      bodyLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: textPrimary,
        height: 1.5,
      ),
      bodyMedium: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: textPrimary,
        height: 1.5,
      ),
      // Caption — secondary labels, timestamps.
      labelSmall: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w400,
        color: textSecondary,
        height: 1.4,
      ),
      labelMedium: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: textSecondary,
        height: 1.4,
        letterSpacing: 0.02,
      ),
    ).apply(fontFamily: fontFamily);
  }

  /// Numeric readouts (battery %, altitude, RSS dBm) — always tabular so
  /// digits align in columns, per the design system.
  static TextStyle numeric({
    required Color color,
    double fontSize = 15,
    FontWeight fontWeight = FontWeight.w600,
  }) {
    return TextStyle(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      fontFamily: fontFamily,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }
}
