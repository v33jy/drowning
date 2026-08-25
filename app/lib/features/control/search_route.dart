import 'package:latlong2/latlong.dart';

import '../../models/grid_cell.dart';

List<String> optimizeCandidateRoute({
  required LatLng start,
  required Map<String, CellBounds> grid,
  required Iterable<String> candidateIds,
}) {
  final remaining = candidateIds.where(grid.containsKey).toSet();
  final route = <String>[];
  var current = start;
  while (remaining.isNotEmpty) {
    final next = remaining.reduce(
      (a, b) =>
          _distance(current, _center(grid[a]!)) <=
              _distance(current, _center(grid[b]!))
          ? a
          : b,
    );
    route.add(next);
    current = _center(grid[next]!);
    remaining.remove(next);
  }

  var improved = true;
  while (improved) {
    improved = false;
    for (var i = 0; i < route.length - 1; i++) {
      for (var j = i + 1; j < route.length; j++) {
        final candidate = [...route];
        candidate.replaceRange(i, j + 1, route.sublist(i, j + 1).reversed);
        if (_routeLength(start, candidate, grid) + 0.01 <
            _routeLength(start, route, grid)) {
          route
            ..clear()
            ..addAll(candidate);
          improved = true;
        }
      }
    }
  }
  return route;
}

LatLng candidateCellCenter(CellBounds bounds) => _center(bounds);

LatLng _center(CellBounds bounds) => LatLng(
  (bounds.latMin + bounds.latMax) / 2,
  (bounds.lngMin + bounds.lngMax) / 2,
);

double _routeLength(
  LatLng start,
  List<String> route,
  Map<String, CellBounds> grid,
) {
  var total = 0.0;
  var current = start;
  for (final id in route) {
    final next = _center(grid[id]!);
    total += _distance(current, next);
    current = next;
  }
  return total;
}

double _distance(LatLng a, LatLng b) =>
    const Distance().as(LengthUnit.Meter, a, b);
