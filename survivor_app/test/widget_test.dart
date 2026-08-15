import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:survivor_app/main.dart';

void main() {
  test('로컬 signaling URL을 만든다', () {
    expect(
      ServerConfig.ws('/survivors/listen'),
      'ws://localhost:8000/survivors/listen',
    );
  });

  testWidgets('통화 단계별 상태 문구를 표시한다', (tester) async {
    final controller = SurvivorCallController();
    await tester.pumpWidget(
      MaterialApp(home: CallScreen(controller: controller, autoStart: false)),
    );

    expect(find.text('통화 대기 중'), findsOneWidget);
    controller.dispose();
  });
}
