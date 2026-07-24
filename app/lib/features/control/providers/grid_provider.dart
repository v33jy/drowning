import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../models/grid_cell.dart';

/// Grid definition — fetched over HTTP during boot (and again if 설정
/// 화면 changes the server address), then otherwise read-only.
final gridDefProvider = StateProvider<Map<String, CellBounds>>((ref) => {});

/// Shared by [BootScreen] and 설정 화면's reconnect action so the fetch +
/// parse logic only exists once.
Future<void> fetchAndApplyGrid(WidgetRef ref, String baseUrl) async {
  final res = await http.get(Uri.parse('$baseUrl/heatmap/grid'));
  if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
  final grid = jsonDecode(res.body) as List<dynamic>;
  ref.read(gridDefProvider.notifier).state = {
    for (final item in grid)
      (item['cell_id'] as String): CellBounds.fromJson(item['bounds'] as Map<String, dynamic>),
  };
}
