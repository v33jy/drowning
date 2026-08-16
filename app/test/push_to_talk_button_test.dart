import 'package:control_app/features/detection/push_to_talk_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('starts on hold and stops when the pointer is released', (
    tester,
  ) async {
    var starts = 0;
    var stops = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: PushToTalkButton(
          enabled: true,
          isTransmitting: false,
          onTransmitStart: () => starts++,
          onTransmitEnd: () => stops++,
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.bySemanticsLabel('누르고 말하기')),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(starts, 1);

    await gesture.up();
    await tester.pump();
    expect(stops, 1);
  });

  testWidgets('does not transmit while disabled', (tester) async {
    var starts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: PushToTalkButton(
          enabled: false,
          isTransmitting: false,
          onTransmitStart: () => starts++,
          onTransmitEnd: () {},
        ),
      ),
    );

    await tester.longPress(find.bySemanticsLabel('누르고 말하기'));
    expect(starts, 0);
  });

  testWidgets('stops transmitting when removed during a hold', (tester) async {
    var stops = 0;
    Widget button() => MaterialApp(
      home: PushToTalkButton(
        enabled: true,
        isTransmitting: true,
        onTransmitStart: () {},
        onTransmitEnd: () => stops++,
      ),
    );
    await tester.pumpWidget(button());

    await tester.startGesture(
      tester.getCenter(find.bySemanticsLabel('음성 전달 중')),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpWidget(const SizedBox.shrink());

    expect(stops, 1);
  });
}
