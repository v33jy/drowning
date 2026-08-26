import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:survivor_app/main.dart';

void main() {
  test('로컬 signaling URL을 만든다', () {
    expect(
      ServerConfig.ws('/survivors/listen'),
      'ws://localhost:8001/survivors/listen',
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

  testWidgets('재연결 중에도 통화를 종료할 수 있다', (tester) async {
    final controller = SurvivorCallController()..phase = CallPhase.reconnecting;
    await tester.pumpWidget(
      MaterialApp(home: CallScreen(controller: controller, autoStart: false)),
    );

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '통화 종료'),
    );
    expect(button.onPressed, isNotNull);
    controller.dispose();
  });

  testWidgets('통화 화면에서 일반 양방향 통화만 표시한다', (tester) async {
    final controller = SurvivorCallController()..phase = CallPhase.active;
    await tester.pumpWidget(
      MaterialApp(home: CallScreen(controller: controller, autoStart: false)),
    );

    expect(find.text('마이크 음소거'), findsOneWidget);
    expect(find.text('길게 눌러 말하기'), findsNothing);
    expect(find.text('눌러서 말하기'), findsNothing);

    controller.dispose();
  });
}
