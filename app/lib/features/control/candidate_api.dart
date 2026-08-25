import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../config.dart';

class CandidateApiException implements Exception {
  const CandidateApiException(this.operation, this.statusCode);

  final String operation;
  final int statusCode;

  @override
  String toString() => '$operation failed with HTTP $statusCode';
}

Future<void> reviewCandidateRequest({
  required String cellId,
  required String outcome,
  http.Client? client,
}) async {
  final uri = Uri.parse('${Config.baseUrl}/search/candidates/$cellId');
  final body = jsonEncode({'outcome': outcome});
  final response = client == null
      ? await http.put(uri, headers: _jsonHeaders, body: body)
      : await client.put(uri, headers: _jsonHeaders, body: body);
  _ensureSuccess(response, '후보 처리');
}

Future<void> reportCandidateDetection({
  required int droneId,
  required String cellId,
  required double signal,
  required String streamUrl,
  http.Client? client,
}) async {
  final uri = Uri.parse('${Config.baseUrl}/detection');
  final body = jsonEncode({
    'drone_id': droneId,
    'cell_id': cellId,
    'rss_dbm': signal,
    'stream_url': streamUrl,
  });
  final response = client == null
      ? await http.post(uri, headers: _jsonHeaders, body: body)
      : await client.post(uri, headers: _jsonHeaders, body: body);
  _ensureSuccess(response, '후보 탐지');
}

void _ensureSuccess(http.Response response, String operation) {
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw CandidateApiException(operation, response.statusCode);
  }
}

const _jsonHeaders = {'Content-Type': 'application/json'};
