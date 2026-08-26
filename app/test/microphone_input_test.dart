import 'package:control_app/features/detection/microphone_input_indicator.dart';
import 'package:control_app/services/call_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('마이크 입력 상태에 맞는 구조대원 안내를 표시한다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MicrophoneInputIndicator(
            status: MicrophoneInputStatus.silent,
            level: 0,
          ),
        ),
      ),
    );

    expect(find.text('마이크 소리가 감지되지 않습니다'), findsOneWidget);
  });
}
