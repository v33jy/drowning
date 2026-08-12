import 'package:latlong2/latlong.dart';

class CellBounds {
  final double latMin;
  final double latMax;
  final double lngMin;
  final double lngMax;

  const CellBounds({
    required this.latMin,
    required this.latMax,
    required this.lngMin,
    required this.lngMax,
  });

  LatLng get northWest => LatLng(latMax, lngMin);
  LatLng get southEast => LatLng(latMin, lngMax);

  bool contains(
    LatLng point, {
    bool includeLatMax = true,
    bool includeLngMax = true,
  }) =>
      point.latitude >= latMin &&
      (point.latitude < latMax ||
          (includeLatMax && point.latitude == latMax)) &&
      point.longitude >= lngMin &&
      (point.longitude < lngMax ||
          (includeLngMax && point.longitude == lngMax));

  factory CellBounds.fromJson(Map<String, dynamic> json) => CellBounds(
    latMin: (json['lat_min'] as num).toDouble(),
    latMax: (json['lat_max'] as num).toDouble(),
    lngMin: (json['lng_min'] as num).toDouble(),
    lngMax: (json['lng_max'] as num).toDouble(),
  );
}

String? findContainingCellId(Map<String, CellBounds> grid, LatLng point) {
  if (grid.isEmpty) return null;
  final outerLatMax = grid.values
      .map((bounds) => bounds.latMax)
      .reduce((a, b) => a > b ? a : b);
  final outerLngMax = grid.values
      .map((bounds) => bounds.lngMax)
      .reduce((a, b) => a > b ? a : b);

  for (final entry in grid.entries) {
    final bounds = entry.value;
    if (bounds.contains(
      point,
      includeLatMax: bounds.latMax == outerLatMax,
      includeLngMax: bounds.lngMax == outerLngMax,
    )) {
      return entry.key;
    }
  }
  return null;
}
