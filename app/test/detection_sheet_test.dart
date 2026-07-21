import 'package:control_app/features/detection/detection_sheet.dart';
import 'package:control_app/models/detection_event.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final event = DetectionEvent(
    droneId: 1,
    cellId: 'C4',
    rssDbm: -41.5,
    timestamp: DateTime.now().millisecondsSinceEpoch / 1000,
    voipSessionId: 'test-session',
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

  testWidgets('통화 전엔 구조 완료 버튼이 보이지 않는다', (tester) async {
    await pumpSheet(tester);

    expect(find.text('통화 연결'), findsOneWidget);
    expect(find.text('오탐 처리'), findsOneWidget);
    expect(find.text('최소화'), findsOneWidget);
    expect(find.text('구조 완료'), findsNothing);
  });

  testWidgets('오탐 처리는 확인 다이얼로그 없이 바로 처리되지 않는다', (tester) async {
    await pumpSheet(tester);

    await tester.tap(find.text('오탐 처리'));
    await tester.pumpAndSettle();

    expect(find.text('오탐으로 처리할까요?'), findsOneWidget);
    // 다이얼로그가 뜬 시점엔 아직 시트가 닫히지 않아야 한다.
    expect(find.text('통화 연결'), findsOneWidget);
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

    await tester.tap(find.text('최소화'));
    await tester.pumpAndSettle();

    expect(find.text('outcome:minimized'), findsOneWidget);
  });
}
