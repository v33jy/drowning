import 'package:control_app/features/detection/detection_sheet.dart';
import 'package:control_app/models/detection_event.dart';
import 'package:control_app/services/call_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final event = DetectionEvent(
    droneId: 1,
    cellId: 'C4',
    rssDbm: -41.5,
    timestamp: DateTime.now().millisecondsSinceEpoch / 1000,
    detectionId: 'test-detection',
    callSessionId: 'test-call',
  );

  Future<void> pumpSheet(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDetectionSheet(context, event),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> pumpSheetWithCallState(
    WidgetTester tester,
    CallState callState,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          callServiceProvider.overrideWith((ref) => TestCallService(callState)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDetectionSheet(context, event),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('구조 완료 버튼과 오탐/최소화 아이콘이 보인다', (tester) async {
    await pumpSheet(tester);

    expect(find.text('구조 완료'), findsOneWidget);
    expect(find.text('전화 연결'), findsOneWidget);
    expect(find.byIcon(Icons.flag_outlined), findsOneWidget);
    expect(find.byIcon(Icons.remove_circle_outline), findsOneWidget);
  });

  testWidgets('오탐 처리는 확인 다이얼로그 없이 바로 처리되지 않는다', (tester) async {
    await pumpSheet(tester);

    await tester.tap(find.byIcon(Icons.flag_outlined));
    await tester.pumpAndSettle();

    expect(find.text('오탐으로 처리할까요?'), findsOneWidget);
    // 다이얼로그가 뜬 시점엔 아직 시트가 닫히지 않아야 한다.
    expect(find.text('구조 완료'), findsOneWidget);
  });

  testWidgets('최소화는 시트를 닫되 큐에서 제거하지 않는다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  final outcome = await showDetectionSheet(context, event);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('outcome:${outcome?.name}')),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.remove_circle_outline));
    await tester.pumpAndSettle();

    expect(find.text('outcome:minimized'), findsOneWidget);
  });

  testWidgets('통화 세션이 없는 탐지에는 PTT를 표시하지 않는다', (tester) async {
    final eventWithoutCall = DetectionEvent(
      droneId: 1,
      cellId: 'C4',
      rssDbm: -41.5,
      timestamp: DateTime.now().millisecondsSinceEpoch / 1000,
      detectionId: 'without-call',
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDetectionSheet(context, eventWithoutCall),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('길게 눌러 말하기'), findsNothing);
    expect(find.text('통화가 연결되면 사용할 수 있습니다'), findsNothing);
  });

  testWidgets('재연결 상태와 진행 횟수를 표시한다', (tester) async {
    await pumpSheetWithCallState(
      tester,
      const CallState(
        CallStatus.reconnecting,
        sessionId: 'test-call',
        retryAttempt: 2,
      ),
    );

    expect(find.text('재연결 중'), findsOneWidget);
    expect(find.text('연결 끊김 · 자동 재연결 2/3'), findsOneWidget);
  });

  testWidgets('자동 재연결 실패 후 수동 재시도 버튼을 표시한다', (tester) async {
    await pumpSheetWithCallState(
      tester,
      const CallState(
        CallStatus.disconnected,
        sessionId: 'test-call',
        message: '음성 연결에 실패했습니다. 다시 시도해 주세요.',
      ),
    );

    expect(find.text('다시 연결'), findsOneWidget);
    expect(find.textContaining('다시 시도해 주세요'), findsOneWidget);
  });

  testWidgets('마이크 권한이 영구 거부되면 설정 이동을 안내한다', (tester) async {
    await pumpSheetWithCallState(
      tester,
      const CallState(
        CallStatus.disconnected,
        sessionId: 'test-call',
        message: '마이크 권한이 꺼져 있습니다. 기기 설정에서 권한을 허용하세요.',
        recoveryAction: CallRecoveryAction.openMicrophoneSettings,
      ),
    );

    expect(find.text('권한 설정'), findsOneWidget);
    expect(find.byIcon(Icons.settings), findsOneWidget);
    expect(find.textContaining('기기 설정에서 권한을 허용하세요'), findsOneWidget);
    expect(find.text('다시 연결'), findsNothing);
  });
}

class TestCallService extends CallService {
  TestCallService(CallState initialState) {
    state = initialState;
  }
}
