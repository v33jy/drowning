import 'package:control_app/features/control/search_route.dart';
import 'package:control_app/models/grid_cell.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  test('orders candidate cells from the current drone position', () {
    const grid = <String, CellBounds>{
      'A0': CellBounds(latMin: 0, latMax: 1, lngMin: 0, lngMax: 1),
      'A1': CellBounds(latMin: 0, latMax: 1, lngMin: 1, lngMax: 2),
      'A2': CellBounds(latMin: 0, latMax: 1, lngMin: 2, lngMax: 3),
    };

    final route = optimizeCandidateRoute(
      start: const LatLng(0.5, 0.4),
      grid: grid,
      candidateIds: const ['A2', 'A1'],
    );

    expect(route, ['A1', 'A2']);
  });

  test('ignores a reviewed cell removed from candidate ids', () {
    const grid = <String, CellBounds>{
      'A0': CellBounds(latMin: 0, latMax: 1, lngMin: 0, lngMax: 1),
      'A1': CellBounds(latMin: 0, latMax: 1, lngMin: 1, lngMax: 2),
    };

    final route = optimizeCandidateRoute(
      start: const LatLng(0.5, 0.4),
      grid: grid,
      candidateIds: const ['A1'],
    );

    expect(route, ['A1']);
    expect(route, isNot(contains('A0')));
  });
}
