import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../models/grid_cell.dart';
import '../../../models/heatmap_cell.dart';
import '../../../models/search_area_presentation.dart';
import '../providers/grid_provider.dart';
import '../providers/heatmap_provider.dart';

/// RSS 구역을 지도 좌표 기반 폴리곤으로 표시한다.
/// 화면 픽셀을 직접 계산하면 지도 이동·확대 후 원점이 어긋날 수 있으므로
/// flutter_map이 각 모서리를 투영하도록 맡긴다.
class HeatmapLayer extends ConsumerWidget {
  const HeatmapLayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gridDef = ref.watch(gridDefProvider);
    final cells = ref.watch(heatmapProvider);
    if (gridDef.isEmpty) return const SizedBox.shrink();

    return PolygonLayer(
      polygons: [
        _buildSearchBoundary(gridDef.values),
        for (final entry in cells.entries)
          if (!entry.value.isUnscanned)
            if (gridDef[entry.key] case final bounds?)
              _buildPolygon(entry.value, bounds),
      ],
    );
  }

  Polygon _buildSearchBoundary(Iterable<CellBounds> cells) {
    final latMin = cells.map((cell) => cell.latMin).reduce(mathMin);
    final latMax = cells.map((cell) => cell.latMax).reduce(mathMax);
    final lngMin = cells.map((cell) => cell.lngMin).reduce(mathMin);
    final lngMax = cells.map((cell) => cell.lngMax).reduce(mathMax);
    return Polygon(
      points: [
        LatLng(latMax, lngMin),
        LatLng(latMax, lngMax),
        LatLng(latMin, lngMax),
        LatLng(latMin, lngMin),
      ],
      color: Colors.transparent,
      borderColor: const Color(0xFF173B67),
      borderStrokeWidth: 2,
    );
  }

  Polygon _buildPolygon(HeatmapCell cell, CellBounds bounds) => Polygon(
    points: [
      LatLng(bounds.latMax, bounds.lngMin),
      LatLng(bounds.latMax, bounds.lngMax),
      LatLng(bounds.latMin, bounds.lngMax),
      LatLng(bounds.latMin, bounds.lngMin),
    ],
    color: heatmapDisplayColor(
      cell,
    ).withValues(alpha: _fillOpacity(cell.status)),
    borderColor: cell.needsRecheck || cell.status == SearchAreaStatus.confirmed
        ? heatmapDisplayColor(cell)
        : Colors.transparent,
    borderStrokeWidth:
        cell.needsRecheck || cell.status == SearchAreaStatus.confirmed
        ? 1.2
        : 0,
  );

  double _fillOpacity(SearchAreaStatus status) => switch (status) {
    SearchAreaStatus.unscanned => 0,
    SearchAreaStatus.scanning => 0.35,
    SearchAreaStatus.needsRecheck => 0.62,
    SearchAreaStatus.cleared => 0.18,
    SearchAreaStatus.confirmed => 0.72,
  };
}

double mathMin(double a, double b) => a < b ? a : b;
double mathMax(double a, double b) => a > b ? a : b;

Color heatmapDisplayColor(HeatmapCell cell) => switch (cell.status) {
  SearchAreaStatus.confirmed => SearchAreaColors.survivorFound,
  SearchAreaStatus.cleared => SearchAreaColors.falseAlarm,
  SearchAreaStatus.unscanned => Colors.transparent,
  SearchAreaStatus.needsRecheck => SearchAreaColors.candidate,
  SearchAreaStatus.scanning => signalStrengthPresentation(
    cell.rssDbm ?? cell.latestRssDbm ?? -100,
  ).color,
};
