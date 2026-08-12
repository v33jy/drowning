import 'package:flutter/material.dart';

enum SearchAreaStatus {
  unscanned,
  scanning,
  needsRecheck;

  factory SearchAreaStatus.fromJson(String value) => switch (value) {
    'scanning' || 'active' => SearchAreaStatus.scanning,
    'needs_recheck' => SearchAreaStatus.needsRecheck,
    _ => SearchAreaStatus.unscanned,
  };
}

class HeatmapCell {
  final String cellId;
  final int? droneId;
  final double? rssDbm;
  final String colorHex;
  final SearchAreaStatus status;
  final double? latestRssDbm;
  final double? averageRssDbm;
  final double? peakRssDbm;
  final int sampleCount;
  final int droneCount;
  final int strongSignalCount;
  final String statusReason;
  final DateTime? lastUpdated;

  const HeatmapCell({
    required this.cellId,
    required this.colorHex,
    required this.status,
    this.droneId,
    this.rssDbm,
    this.latestRssDbm,
    this.averageRssDbm,
    this.peakRssDbm,
    this.sampleCount = 0,
    this.droneCount = 0,
    this.strongSignalCount = 0,
    this.statusReason = 'no_measurements',
    this.lastUpdated,
  });

  Color get color {
    final hex = colorHex.replaceFirst('#', '');
    return Color(int.parse('FF$hex', radix: 16));
  }

  bool get isUnscanned => status == SearchAreaStatus.unscanned;
  bool get needsRecheck => status == SearchAreaStatus.needsRecheck;

  factory HeatmapCell.unscanned(String cellId) => HeatmapCell(
    cellId: cellId,
    colorHex: '#404040',
    status: SearchAreaStatus.unscanned,
  );

  factory HeatmapCell.fromJson(Map<String, dynamic> json) => HeatmapCell(
    cellId: json['cell_id'] as String,
    colorHex: json['color'] as String,
    status: SearchAreaStatus.fromJson(json['status'] as String),
    droneId: json['drone_id'] as int?,
    rssDbm: (json['rss_dbm'] as num?)?.toDouble(),
    latestRssDbm: (json['latest_rss_dbm'] as num?)?.toDouble(),
    averageRssDbm: (json['average_rss_dbm'] as num?)?.toDouble(),
    peakRssDbm: (json['peak_rss_dbm'] as num?)?.toDouble(),
    sampleCount: (json['sample_count'] as num?)?.toInt() ?? 0,
    droneCount: (json['drone_count'] as num?)?.toInt() ?? 0,
    strongSignalCount: (json['strong_signal_count'] as num?)?.toInt() ?? 0,
    statusReason: json['status_reason'] as String? ?? 'no_measurements',
    lastUpdated: _unixSeconds(json['last_updated'] as num?),
  );

  static DateTime? _unixSeconds(num? value) => value == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(
          (value * 1000).round(),
          isUtc: true,
        );
}
