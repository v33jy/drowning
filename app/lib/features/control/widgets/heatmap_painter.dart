import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/grid_cell.dart';
import '../../../models/heatmap_cell.dart';
import '../providers/grid_provider.dart';
import '../providers/heatmap_provider.dart';

/// Radio-signal heatmap. Only this widget rebuilds when heatmap cells
/// change — never the map or markers.
class HeatmapPainterLayer extends ConsumerWidget {
  const HeatmapPainterLayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gridDef = ref.watch(gridDefProvider);
    final cells = ref.watch(heatmapProvider);
    if (gridDef.isEmpty) return const SizedBox.shrink();

    final camera = MapCamera.of(context);
    return CustomPaint(
      painter: _HeatmapPainter(cells: cells, gridDef: gridDef, camera: camera),
      // Size.infinite paints nothing — SizedBox.expand gives the full map size.
      child: const SizedBox.expand(),
    );
  }
}

class _HeatmapPainter extends CustomPainter {
  const _HeatmapPainter({
    required this.cells,
    required this.gridDef,
    required this.camera,
  });

  final Map<String, HeatmapCell> cells;
  final Map<String, CellBounds> gridDef;
  final MapCamera camera;

  @override
  void paint(Canvas canvas, Size size) {
    for (final entry in cells.entries) {
      final bounds = gridDef[entry.key];
      if (bounds == null) continue;
      final cell = entry.value;

      // getOffsetFromOrigin() gives layer-space coordinates for widgets
      // that live inside FlutterMap's children — screen-space APIs give
      // the wrong offset here.
      final nw = camera.getOffsetFromOrigin(bounds.northWest);
      final se = camera.getOffsetFromOrigin(bounds.southEast);
      final rect = Rect.fromPoints(nw, se);
      final opacity = cell.isUnscanned ? 0.12 : 0.60;

      canvas.drawRect(rect, Paint()..color = cell.color.withValues(alpha: opacity));
    }
  }

  @override
  bool shouldRepaint(_HeatmapPainter oldDelegate) =>
      oldDelegate.cells != cells || oldDelegate.camera != camera;
}
