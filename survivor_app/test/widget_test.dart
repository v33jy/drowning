import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:survivor_app/main.dart';
import 'package:survivor_app/push_to_talk_button.dart';

void main() {
  test('로컬 signaling URL을 만든다', () {
    expect(
      ServerConfig.ws('/survivors/listen'),
      'ws://localhost:8000/survivors/listen',
    );
  });

  testWidgets('PTT는 길게 누르는 동안만 송신한다', (tester) async {
    var starts = 0;
    var stops = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SurvivorPushToTalkButton(
            isTransmitting: false,
            onTransmitStart: () => starts++,
            onTransmitEnd: () => stops++,
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('길게 눌러 말하기')),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(starts, 1);

    await gesture.up();
    await tester.pump();
    expect(stops, 1);
  });

  testWidgets('PTT 중 화면이 닫히면 송신을 중단한다', (tester) async {
    var stops = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SurvivorPushToTalkButton(
          isTransmitting: true,
          onTransmitStart: () {},
          onTransmitEnd: () => stops++,
        ),
      ),
    );

    await tester.startGesture(tester.getCenter(find.text('말하는 중 · 놓으면 음소거')));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpWidget(const SizedBox.shrink());

    expect(stops, 1);
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
}
