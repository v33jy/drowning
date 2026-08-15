import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../models/video_bookmark.dart';
import '../../settings/providers/settings_provider.dart';

const _captureRefreshInterval = Duration(seconds: 1);

final videoBookmarksProvider = StreamProvider.autoDispose
    .family<List<VideoBookmark>, String>((ref, cellId) async* {
      final baseUrl = ref.watch(settingsProvider).baseUrl;
      while (true) {
        final bookmarks = await _fetchBookmarks(baseUrl, cellId);
        yield bookmarks;
        if (bookmarks.isEmpty || bookmarks.every((item) => item.complete)) {
          return;
        }
        await Future<void>.delayed(_captureRefreshInterval);
      }
    });

Future<List<VideoBookmark>> _fetchBookmarks(
  String baseUrl,
  String cellId,
) async {
  final uri = Uri.parse(
    '$baseUrl/drones/video/bookmarks',
  ).replace(queryParameters: {'cell_id': cellId});
  final response = await http.get(uri);
  if (response.statusCode != 200) {
    throw Exception('HTTP ${response.statusCode}');
  }
  final items = jsonDecode(response.body) as List<dynamic>;
  return items
      .map((item) => VideoBookmark.fromJson(item as Map<String, dynamic>))
      .toList(growable: false);
}
