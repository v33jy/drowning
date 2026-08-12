import 'package:control_app/models/grid_cell.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  const bounds = CellBounds(
    latMin: 37.49,
    latMax: 37.50,
    lngMin: 127.02,
    lngMax: 127.03,
  );

  test('contains a point inside the search cell', () {
    expect(bounds.contains(const LatLng(37.495, 127.025)), isTrue);
  });

  test('rejects a point outside the search cell', () {
    expect(bounds.contains(const LatLng(37.51, 127.025)), isFalse);
  });

  test('finds the cell containing a map point', () {
    final grid = {'A0': bounds};

    expect(findContainingCellId(grid, const LatLng(37.495, 127.025)), 'A0');
    expect(findContainingCellId(grid, const LatLng(37.51, 127.025)), isNull);
  });
}
