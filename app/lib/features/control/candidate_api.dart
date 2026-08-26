import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../config.dart';

class CandidateApiException implements Exception {
  const CandidateApiException(this.operation, {this.statusCode, this.cause});

  final String operation;
  final int? statusCode;
  final Object? cause;

  @override
  String toString() => statusCode == null
      ? '$operation network request failed: $cause'
      : '$operation failed with HTTP $statusCode';
}

const _requestTimeout = Duration(seconds: 8);

Future<void> reviewCandidateRequest({
  required String cellId,
  required String outcome,
  http.Client? client,
  Duration timeout = _requestTimeout,
}) async {
  final uri = Uri.parse('${Config.baseUrl}/search/candidates/$cellId');
  final body = jsonEncode({'outcome': outcome});
  final response = await _request(
    '후보 처리',
    () => client == null
        ? http.put(uri, headers: _jsonHeaders, body: body)
        : client.put(uri, headers: _jsonHeaders, body: body),
    timeout,
  );
  _ensureSuccess(response, '후보 처리');
}

Future<void> reportCandidateDetection({
  required int droneId,
  required String cellId,
  required double signal,
  required String streamUrl,
  http.Client? client,
  Duration timeout = _requestTimeout,
}) async {
  final uri = Uri.parse('${Config.baseUrl}/detection');
  final body = jsonEncode({
    'drone_id': droneId,
    'cell_id': cellId,
    'rss_dbm': signal,
    'stream_url': streamUrl,
  });
  final response = await _request(
    '후보 탐지',
    () => client == null
        ? http.post(uri, headers: _jsonHeaders, body: body)
        : client.post(uri, headers: _jsonHeaders, body: body),
    timeout,
  );
  _ensureSuccess(response, '후보 탐지');
}

void _ensureSuccess(http.Response response, String operation) {
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw CandidateApiException(operation, statusCode: response.statusCode);
  }
}

Future<http.Response> _request(
  String operation,
  Future<http.Response> Function() send,
  Duration timeout,
) async {
  try {
    return await send().timeout(timeout);
  } on TimeoutException catch (error) {
    throw CandidateApiException(operation, cause: error);
  } on http.ClientException catch (error) {
    throw CandidateApiException(operation, cause: error);
  }
}

const _jsonHeaders = {'Content-Type': 'application/json'};
