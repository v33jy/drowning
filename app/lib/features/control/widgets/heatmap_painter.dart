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

  // Satellite photo tiles carry far more visual noise than the old flat
  // basemap, so every overlay below needs a deliberate contrast boost:
  // a black-then-white halo stroke that reads over any terrain color, and
  // heavier fill opacity than a flat basemap would need.
  static const _haloOuterWidth = 5.0;
  static const _haloInnerWidth = 2.5;
  static const _cellBorderWidth = 1.5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gridDef = ref.watch(gridDefProvider);
    final cells = ref.watch(heatmapProvider);
    if (gridDef.isEmpty) return const SizedBox.shrink();

    return PolygonLayer(
      polygons: [
        ..._buildSearchBoundary(gridDef.values),
        for (final entry in cells.entries)
          if (!entry.value.isUnscanned)
            if (gridDef[entry.key] case final bounds?)
              _buildPolygon(entry.value, bounds),
      ],
    );
  }

  /// White line over a wider black halo so the boundary stays visible
  /// regardless of the satellite tile's underlying color at that spot.
  List<Polygon> _buildSearchBoundary(Iterable<CellBounds> cells) {
    final latMin = cells.map((cell) => cell.latMin).reduce(mathMin);
    final latMax = cells.map((cell) => cell.latMax).reduce(mathMax);
    final lngMin = cells.map((cell) => cell.lngMin).reduce(mathMin);
    final lngMax = cells.map((cell) => cell.lngMax).reduce(mathMax);
    final points = [
      LatLng(latMax, lngMin),
      LatLng(latMax, lngMax),
      LatLng(latMin, lngMax),
      LatLng(latMin, lngMin),
    ];
    return [
      Polygon(
        points: points,
        color: Colors.transparent,
        borderColor: Colors.black,
        borderStrokeWidth: _haloOuterWidth,
      ),
      Polygon(
        points: points,
        color: Colors.transparent,
        borderColor: Colors.white,
        borderStrokeWidth: _haloInnerWidth,
      ),
    ];
  }

  Polygon _buildPolygon(HeatmapCell cell, CellBounds bounds) {
    final isHighlighted =
        cell.needsRecheck || cell.status == SearchAreaStatus.confirmed;
    return Polygon(
      points: [
        LatLng(bounds.latMax, bounds.lngMin),
        LatLng(bounds.latMax, bounds.lngMax),
        LatLng(bounds.latMin, bounds.lngMax),
        LatLng(bounds.latMin, bounds.lngMin),
      ],
      color: heatmapDisplayColor(
        cell,
      ).withValues(alpha: _fillOpacity(cell.status)),
      // White rather than the cell's own color — a same-hue border on a
      // same-hue fill disappears, same reasoning as the boundary halo above.
      borderColor: isHighlighted ? Colors.white : Colors.transparent,
      borderStrokeWidth: isHighlighted ? _cellBorderWidth : 0,
    );
  }

  // Pulled back down from the initial satellite-contrast pass — full
  // strength across every status buried the imagery under color. Trimmed
  // roughly evenly so the basemap reads through while needsRecheck/confirmed
  // still stand out as the cells that actually need attention.
  double _fillOpacity(SearchAreaStatus status) => switch (status) {
    SearchAreaStatus.unscanned => 0,
    SearchAreaStatus.scanning => 0.38,
    SearchAreaStatus.needsRecheck => 0.60,
    SearchAreaStatus.cleared => 0.16,
    SearchAreaStatus.confirmed => 0.68,
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
