import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../models/grid_cell.dart';

/// Grid definition — fetched over HTTP during boot (and again if 설정
/// 화면 changes the server address), then otherwise read-only.
final gridDefProvider = StateProvider<Map<String, CellBounds>>((ref) => {});
final gridLocationLabelProvider = StateProvider<Map<String, String>>(
  (ref) => {},
);

String locationLabelForCell({
  required String cellId,
  required Map<String, String> labels,
  required Map<String, CellBounds> grid,
}) {
  final landmark = labels[cellId];
  if (landmark != null && landmark.isNotEmpty) return landmark;
  final target = grid[cellId];
  if (target == null || labels.isEmpty) return '위치 정보 없음';

  final targetLat = (target.latMin + target.latMax) / 2;
  final targetLng = (target.lngMin + target.lngMax) / 2;
  ({String name, double lat, double lng, double distance})? nearest;
  for (final entry in labels.entries) {
    final anchor = grid[entry.key];
    if (anchor == null || entry.value.isEmpty) continue;
    final anchorLat = (anchor.latMin + anchor.latMax) / 2;
    final anchorLng = (anchor.lngMin + anchor.lngMax) / 2;
    final distance = _distanceMeters(
      targetLat,
      targetLng,
      anchorLat,
      anchorLng,
    );
    if (nearest == null || distance < nearest.distance) {
      nearest = (
        name: entry.value.replaceFirst(RegExp(r'\s*인근$'), ''),
        lat: anchorLat,
        lng: anchorLng,
        distance: distance,
      );
    }
  }
  if (nearest == null) return '위치 정보 없음';
  final direction = _directionFrom(
    nearest.lat,
    nearest.lng,
    targetLat,
    targetLng,
  );
  final roundedMeters = (nearest.distance / 10).round() * 10;
  return '${nearest.name} $direction 약 ${roundedMeters}m';
}

double _distanceMeters(double lat1, double lng1, double lat2, double lng2) {
  final north = (lat1 - lat2) * 111320;
  final east =
      (lng1 - lng2) * 111320 * math.cos(((lat1 + lat2) / 2) * math.pi / 180);
  return math.sqrt(north * north + east * east);
}

String _directionFrom(
  double anchorLat,
  double anchorLng,
  double targetLat,
  double targetLng,
) {
  const directions = ['북쪽', '북동쪽', '동쪽', '남동쪽', '남쪽', '남서쪽', '서쪽', '북서쪽'];
  final north = targetLat - anchorLat;
  final east = targetLng - anchorLng;
  final angle = (math.atan2(east, north) * 180 / math.pi + 360) % 360;
  return directions[((angle / 45).round()) % directions.length];
}

/// Fetched once by [BootScreen] during connect.
Future<void> fetchAndApplyGrid(WidgetRef ref, String baseUrl) async {
  final res = await http.get(Uri.parse('$baseUrl/heatmap/grid'));
  if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
  final grid = jsonDecode(res.body) as List<dynamic>;
  ref.read(gridDefProvider.notifier).state = {
    for (final item in grid)
      (item['cell_id'] as String): CellBounds.fromJson(
        item['bounds'] as Map<String, dynamic>,
      ),
  };
  ref.read(gridLocationLabelProvider.notifier).state = {
    for (final item in grid)
      if ((item['location_label'] as String?)?.isNotEmpty ?? false)
        (item['cell_id'] as String): item['location_label'] as String,
  };
}
