import 'dart:async';

import 'package:control_app/features/control/candidate_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('후보 처리가 2xx가 아니면 실패로 보고한다', () async {
    final client = MockClient((_) async => http.Response('conflict', 409));

    await expectLater(
      reviewCandidateRequest(
        cellId: 'A0',
        outcome: 'false_alarm',
        client: client,
      ),
      throwsA(
        isA<CandidateApiException>().having(
          (error) => error.statusCode,
          'statusCode',
          409,
        ),
      ),
    );
  });

  test('후보 처리 timeout을 네트워크 오류로 보고하고 재시도하지 않는다', () async {
    var requestCount = 0;
    final client = MockClient((_) async {
      requestCount++;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return http.Response('{}', 200);
    });

    await expectLater(
      reviewCandidateRequest(
        cellId: 'A0',
        outcome: 'false_alarm',
        client: client,
        timeout: const Duration(milliseconds: 1),
      ),
      throwsA(
        isA<CandidateApiException>()
            .having((error) => error.statusCode, 'statusCode', isNull)
            .having((error) => error.cause, 'cause', isA<TimeoutException>()),
      ),
    );
    expect(requestCount, 1);
  });

  test('후보 탐지가 2xx면 성공한다', () async {
    final client = MockClient((_) async => http.Response('{}', 201));

    await reportCandidateDetection(
      droneId: 1,
      cellId: 'A0',
      signal: -60,
      streamUrl: 'http://example.test/video',
      client: client,
    );
  });
}
