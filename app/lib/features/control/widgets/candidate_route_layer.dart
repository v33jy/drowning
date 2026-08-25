import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../models/heatmap_cell.dart';
import '../../../models/grid_cell.dart';
import '../../../models/search_area_presentation.dart';
import '../providers/drones_provider.dart';
import '../providers/grid_provider.dart';
import '../providers/heatmap_provider.dart';
import '../search_route.dart';

class CandidateRouteLayer extends ConsumerStatefulWidget {
  const CandidateRouteLayer({this.highlightedCellId, super.key});

  final String? highlightedCellId;

  @override
  ConsumerState<CandidateRouteLayer> createState() =>
      _CandidateRouteLayerState();
}

class _CandidateRouteLayerState extends ConsumerState<CandidateRouteLayer>
    with SingleTickerProviderStateMixin {
  final List<String> _plannedOrder = [];
  LatLng? _routeStart;
  late final AnimationController _pulseController;
  late final Animation<double> _pulseOpacity;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    _pulseOpacity = Tween<double>(begin: 0.28, end: 1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final grid = ref.watch(gridDefProvider);
    final cells = ref.watch(heatmapProvider);
    final routeCells = cells.values.where(
      (cell) =>
          cell.needsRecheck ||
          cell.status == SearchAreaStatus.cleared ||
          cell.status == SearchAreaStatus.confirmed,
    );
    final drones = ref.watch(dronesProvider);
    if (grid.isEmpty || routeCells.isEmpty || drones.isEmpty) {
      return const SizedBox.shrink();
    }

    final start = drones.values.first.position;
    _routeStart ??= start;
    final unseen = routeCells
        .map((cell) => cell.cellId)
        .where((id) => !_plannedOrder.contains(id));
    if (unseen.isNotEmpty) {
      final extensionStart = _plannedOrder.isEmpty
          ? _routeStart!
          : candidateCellCenter(grid[_plannedOrder.last]!);
      _plannedOrder.addAll(
        optimizeCandidateRoute(
          start: extensionStart,
          grid: grid,
          candidateIds: unseen,
        ),
      );
    }
    final route = _plannedOrder.where(grid.containsKey).toList();
    final hasConfirmed = route.any(
      (id) => cells[id]?.status == SearchAreaStatus.confirmed,
    );
    final nextCellId = hasConfirmed
        ? null
        : route
              .where((id) => cells[id]?.status == SearchAreaStatus.needsRecheck)
              .firstOrNull;
    final pulseCellId = widget.highlightedCellId ?? nextCellId;

    final highlightedBounds = grid[widget.highlightedCellId];
    final camera = MapCamera.of(context);
    return Stack(
      children: [
        if (highlightedBounds != null)
          FadeTransition(
            opacity: _pulseOpacity,
            child: PolygonLayer(
              polygons: [
                Polygon(
                  points: [
                    LatLng(highlightedBounds.latMax, highlightedBounds.lngMin),
                    LatLng(highlightedBounds.latMax, highlightedBounds.lngMax),
                    LatLng(highlightedBounds.latMin, highlightedBounds.lngMax),
                    LatLng(highlightedBounds.latMin, highlightedBounds.lngMin),
                  ],
                  color: const Color(0xFFFFA000).withValues(alpha: 0.5),
                  borderColor: const Color(0xFFFF6F00),
                  borderStrokeWidth: 3,
                ),
              ],
            ),
          ),
        MarkerLayer(
          markers: [
            for (var index = 0; index < route.length; index++)
              Marker(
                point: candidateCellCenter(grid[route[index]]!),
                width: candidateMarkerSize(camera, grid[route[index]]!),
                height: candidateMarkerSize(camera, grid[route[index]]!),
                child: FadeTransition(
                  opacity: route[index] == pulseCellId
                      ? _pulseOpacity
                      : const AlwaysStoppedAnimation(1),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _routeColor(cells[route[index]]!.status),
                      shape: BoxShape.circle,
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Color _routeColor(SearchAreaStatus status) => switch (status) {
    SearchAreaStatus.cleared => SearchAreaColors.falseAlarm,
    SearchAreaStatus.confirmed => SearchAreaColors.survivorFound,
    _ => const Color(0xFF173B67),
  };
}

double candidateMarkerSize(MapCamera camera, CellBounds bounds) {
  final northWest = camera.projectAtZoom(LatLng(bounds.latMax, bounds.lngMin));
  final southEast = camera.projectAtZoom(LatLng(bounds.latMin, bounds.lngMax));
  final cellSide = math.min(
    (southEast.dx - northWest.dx).abs(),
    (southEast.dy - northWest.dy).abs(),
  );
  return candidateMarkerDiameterForCellSide(cellSide);
}

double candidateMarkerDiameterForCellSide(double cellSide) =>
    (cellSide * 0.72).clamp(18.0, 96.0).toDouble();
