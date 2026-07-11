import 'package:flutter/material.dart';

class HeatmapCell {
  final String cellId;
  final int? droneId;
  final double? rssDbm;
  final String colorHex;
  final String status;

  const HeatmapCell({
    required this.cellId,
    required this.colorHex,
    required this.status,
    this.droneId,
    this.rssDbm,
  });

  Color get color {
    final hex = colorHex.replaceFirst('#', '');
    return Color(int.parse('FF$hex', radix: 16));
  }

  bool get isUnscanned => status == 'unscanned';

  factory HeatmapCell.fromJson(Map<String, dynamic> json) => HeatmapCell(
        cellId: json['cell_id'] as String,
        colorHex: json['color'] as String,
        status: json['status'] as String,
        droneId: json['drone_id'] as int?,
        rssDbm: (json['rss_dbm'] as num?)?.toDouble(),
      );
}
