import 'package:control_app/features/detection/microphone_input_indicator.dart';
import 'package:control_app/services/call_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('PTT 중 마이크 입력이 감지되면 입력 상태와 레벨을 갱신한다', (tester) async {
    final service = MicrophoneInputTestCallService(
      levelReader: () async => 0.6,
    );

    service.startTransmitting();
    await tester.pump();

    expect(service.state.microphoneInputStatus, MicrophoneInputStatus.detected);
    expect(service.state.microphoneLevel, 0.6);

    service.stopTransmitting();
    expect(service.state.microphoneInputStatus, MicrophoneInputStatus.idle);
  });

  testWidgets('PTT 중 일정 시간 입력이 없으면 무음 상태로 전환한다', (tester) async {
    final service = MicrophoneInputTestCallService(levelReader: () async => 0);

    service.startTransmitting();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));

    expect(service.state.microphoneInputStatus, MicrophoneInputStatus.silent);
    service.stopTransmitting();
  });

  testWidgets('입력 레벨을 읽을 수 없으면 확인 불가 상태를 표시한다', (tester) async {
    final service = MicrophoneInputTestCallService(
      levelReader: () async => null,
    );

    service.startTransmitting();
    await tester.pump();

    expect(
      service.state.microphoneInputStatus,
      MicrophoneInputStatus.unavailable,
    );
    service.stopTransmitting();
  });

  testWidgets('입력 확인이 다시 가능해지면 무음 감지를 재개한다', (tester) async {
    var readCount = 0;
    final service = MicrophoneInputTestCallService(
      levelReader: () async => readCount++ == 0 ? null : 0,
    );

    service.startTransmitting();
    await tester.pump();
    expect(
      service.state.microphoneInputStatus,
      MicrophoneInputStatus.unavailable,
    );

    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 25));

    expect(service.state.microphoneInputStatus, MicrophoneInputStatus.silent);
    service.stopTransmitting();
  });

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

class MicrophoneInputTestCallService extends CallService {
  MicrophoneInputTestCallService({
    required Future<double?> Function() levelReader,
  }) : super(
         microphoneLevelReader: levelReader,
         microphoneLevelPollInterval: const Duration(milliseconds: 5),
         microphoneSilenceTimeout: const Duration(milliseconds: 20),
       ) {
    state = const CallState(CallStatus.active, sessionId: 'test-call');
  }
}
