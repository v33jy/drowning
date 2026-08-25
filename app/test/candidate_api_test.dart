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
      throwsA(isA<CandidateApiException>()),
    );
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
