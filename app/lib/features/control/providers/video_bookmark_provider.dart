import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../models/video_bookmark.dart';
import '../../settings/providers/settings_provider.dart';

final videoBookmarksProvider = FutureProvider.autoDispose
    .family<List<VideoBookmark>, String>((ref, cellId) async {
      final baseUrl = ref.watch(settingsProvider).baseUrl;
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
    });
