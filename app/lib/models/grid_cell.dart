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

  factory CellBounds.fromJson(Map<String, dynamic> json) => CellBounds(
        latMin: (json['lat_min'] as num).toDouble(),
        latMax: (json['lat_max'] as num).toDouble(),
        lngMin: (json['lng_min'] as num).toDouble(),
        lngMax: (json['lng_max'] as num).toDouble(),
      );
}
