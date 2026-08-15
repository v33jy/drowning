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
}
