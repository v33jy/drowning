import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/grid_cell.dart';
import '../../models/heatmap_cell.dart';

class HeatmapLayer extends StatelessWidget {
  final Map<String, HeatmapCell> cells;
  final Map<String, CellBounds> gridDef;

  const HeatmapLayer({super.key, required this.cells, required this.gridDef});

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return CustomPaint(
      painter: _HeatmapPainter(cells: cells, gridDef: gridDef, camera: camera),
      // SizedBox.expand() gives the canvas the full map size.
      // size: Size.infinite leaves the canvas at Size.zero — nothing gets drawn.
      child: const SizedBox.expand(),
    );
  }
}

class _HeatmapPainter extends CustomPainter {
  final Map<String, HeatmapCell> cells;
  final Map<String, CellBounds> gridDef;
  final MapCamera camera;

  const _HeatmapPainter({
    required this.cells,
    required this.gridDef,
    required this.camera,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final entry in cells.entries) {
      final bounds = gridDef[entry.key];
      if (bounds == null) continue;

      final cell = entry.value;

      // getOffsetFromOrigin() returns layer-space Offset for use inside
      // FlutterMap children. latLngToScreenPoint() is for widgets outside
      // the map (e.g. Positioned) and gives wrong coordinates here.
      final nw = camera.getOffsetFromOrigin(bounds.northWest);
      final se = camera.getOffsetFromOrigin(bounds.southEast);

      final rect = Rect.fromPoints(nw, se);
      final opacity = cell.isUnscanned ? 0.12 : 0.60;

      canvas.drawRect(
        rect,
        Paint()..color = cell.color.withValues(alpha: opacity),
      );
    }
  }

  @override
  bool shouldRepaint(_HeatmapPainter old) =>
      old.cells != cells || old.camera != camera;
}

// -- Drone markers --

Marker droneMarker(int droneId, LatLng position, int battery) => Marker(
      point: position,
      width: 48,
      height: 48,
      child: _DroneIcon(droneId: droneId, battery: battery),
    );

class _DroneIcon extends StatelessWidget {
  final int droneId;
  final int battery;
  const _DroneIcon({required this.droneId, required this.battery});

  @override
  Widget build(BuildContext context) {
    final color = battery > 30 ? Colors.green : Colors.red;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.flight, color: color, size: 28),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            '#$droneId',
            style: const TextStyle(color: Colors.white, fontSize: 10),
          ),
        ),
      ],
    );
  }
}
