import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../models/grid_cell.dart';
import '../../../models/heatmap_cell.dart';
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

    return PolygonLayer(
      polygons: [
        for (final entry in cells.entries)
          if (gridDef[entry.key] case final bounds?)
            _buildPolygon(entry.value, bounds),
      ],
    );
  }

  Polygon _buildPolygon(HeatmapCell cell, CellBounds bounds) => Polygon(
    points: [
      LatLng(bounds.latMax, bounds.lngMin),
      LatLng(bounds.latMax, bounds.lngMax),
      LatLng(bounds.latMin, bounds.lngMax),
      LatLng(bounds.latMin, bounds.lngMin),
    ],
    color: cell.color.withValues(alpha: _fillOpacity(cell.status)),
    borderColor: cell.needsRecheck
        ? cell.color.withValues(alpha: 0.9)
        : Colors.transparent,
    borderStrokeWidth: cell.needsRecheck ? 1.2 : 0,
  );

  double _fillOpacity(SearchAreaStatus status) => switch (status) {
    SearchAreaStatus.unscanned => 0.08,
    SearchAreaStatus.scanning => 0.35,
    SearchAreaStatus.needsRecheck => 0.62,
  };
}
