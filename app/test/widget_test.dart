import 'package:control_app/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('앱 시작 시 Splash 화면이 보인다', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: DroneControlApp()));
    await tester.pump();

    expect(find.text('Mission Control'), findsOneWidget);

    // BootScreen의 800ms 스플래시 딜레이 타이머를 다 흘려보내야 테스트 종료 시
    // "pending timer" 어서션에 걸리지 않는다.
    await tester.pump(const Duration(milliseconds: 900));
  });
}
