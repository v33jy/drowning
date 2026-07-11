import 'package:latlong2/latlong.dart';

class DroneState {
  final int droneId;
  final double lat;
  final double lng;
  final double altitude;
  final int battery;
  final String status;
  final String? cellId;

  const DroneState({
    required this.droneId,
    required this.lat,
    required this.lng,
    required this.altitude,
    required this.battery,
    required this.status,
    this.cellId,
  });

  LatLng get position => LatLng(lat, lng);

  factory DroneState.fromJson(Map<String, dynamic> json) => DroneState(
        droneId: json['drone_id'] as int,
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        altitude: (json['altitude'] as num).toDouble(),
        battery: json['battery'] as int,
        status: json['status'] as String,
        cellId: json['cell_id'] as String?,
      );
}
