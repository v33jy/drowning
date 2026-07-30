import 'package:flutter/material.dart';

/// Typography — single sans family, Bold titles / Regular body only.
class AppTypography {
  AppTypography._();

  static const String fontFamily = 'PublicSans';

  static TextTheme textTheme(Color textPrimary, Color textSecondary) {
    return TextTheme(
      // Display — screen-level headings. Slightly tightened tracking reads
      // more deliberate at this size than default spacing.
      displaySmall: TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.w700,
        color: textPrimary,
        height: 1.25,
        letterSpacing: -0.3,
      ),
      // Title — section/dialog/sheet headers.
      titleLarge: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: textPrimary,
        height: 1.3,
        letterSpacing: -0.1,
      ),
      // titleMedium is used everywhere (card headers, drone ids, tile
      // titles) — w600 rather than w700 so it reads as "a heading" without
      // shouting as loud as titleLarge; when every weight is 700, nothing
      // stands out as more important than anything else.
      titleMedium: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
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
        fontSize: 14.5,
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
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: textSecondary,
        height: 1.4,
        letterSpacing: 0.01,
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

  /// Small uppercase-weight section label (기록/설정 group headers, table
  /// column headers, stat labels) — one definition instead of the same
  /// fontSize/weight/letterSpacing tuple copy-pasted into five widgets.
  static TextStyle eyebrow(Color color) => TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.04,
        color: color,
        fontFamily: fontFamily,
      );
}
