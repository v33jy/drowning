import 'package:control_app/features/control/widgets/search_area_detail_sheet.dart';
import 'package:control_app/features/control/widgets/search_area_guidance.dart';
import 'package:control_app/features/control/providers/grid_provider.dart';
import 'package:control_app/features/control/data/demo_feed.dart';
import 'package:control_app/models/grid_cell.dart';
import 'package:control_app/models/heatmap_cell.dart';
import 'package:control_app/models/video_bookmark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:control_app/features/control/widgets/video_review_section.dart';

void main() {
  test('describes cells relative to the nearest configured landmark', () {
    final label = locationLabelForCell(
      cellId: 'F3',
      labels: const {'F2': '신논현역 인근'},
      grid: const {
        'F2': CellBounds(
          latMin: 37.50,
          latMax: 37.51,
          lngMin: 127.02,
          lngMax: 127.03,
        ),
        'F3': CellBounds(
          latMin: 37.50,
          latMax: 37.51,
          lngMin: 127.03,
          lngMax: 127.04,
        ),
      },
    );

    expect(label, startsWith('신논현역 기준 동쪽 약'));
  });

  test('uses the landmark label for the cell containing it', () {
    final label = locationLabelForCell(
      cellId: 'F2',
      labels: const {'F2': '교보타워 인근'},
      grid: const {},
    );

    expect(label, '교보타워 인근');
  });

  test('offline demo uses the same non-station landmarks as the server', () {
    expect(DemoFeed.locationLabels, {'F2': '교보타워 인근', 'E5': '국기원 인근'});
  });

  test('maps search status to responder-facing guidance', () {
    final cell = HeatmapCell(
      cellId: 'G4',
      colorHex: '#F57C00',
      status: SearchAreaStatus.needsRecheck,
      strongSignalCount: 3,
    );

    final guidance = SearchAreaGuidance.fromCell(cell);

    expect(guidance.statusLabel, '재확인 필요');
    expect(guidance.reason, contains('반복 확인'));
    expect(guidance.action, contains('저고도'));
  });

  test('falls back to status guidance for a missing legacy reason', () {
    final cell = HeatmapCell(
      cellId: 'A0',
      colorHex: '#1976D2',
      status: SearchAreaStatus.scanning,
    );

    final guidance = SearchAreaGuidance.fromCell(cell);

    expect(guidance.reason, contains('신호를 수집'));
  });

  test('formats last checked time for operations', () {
    final now = DateTime.utc(2026, 8, 13, 12);

    expect(formatLastChecked(null, now: now), '확인 기록 없음');
    expect(
      formatLastChecked(now.subtract(const Duration(minutes: 8)), now: now),
      '8분 전',
    );
  });

  testWidgets(
    'shows operational guidance without internal measurement counts',
    (tester) async {
      final cell = HeatmapCell(
        cellId: 'G4',
        colorHex: '#F57C00',
        status: SearchAreaStatus.needsRecheck,
        sampleCount: 7,
        droneCount: 2,
        strongSignalCount: 3,
        lastUpdated: DateTime.now().toUtc(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SearchAreaDetailSheet(cell: cell)),
        ),
      );

      expect(find.text('수색 구역 정보'), findsNothing);
      expect(find.text('수색 구역'), findsNothing);
      expect(find.text('위치 정보 없음'), findsOneWidget);
      expect(find.text('재확인 필요'), findsOneWidget);
      expect(find.text('판단 이유'), findsNothing);
      expect(find.textContaining('다음 행동 지침:'), findsNothing);
      expect(find.textContaining('저고도로 다시 통과'), findsOneWidget);
      expect(find.text('측정 횟수'), findsNothing);
      expect(find.text('확인 드론'), findsNothing);
      expect(find.textContaining('위치를 확정하지 않습니다'), findsNothing);
    },
  );

  testWidgets('opens the confirmation video in a fullscreen dialog', (
    tester,
  ) async {
    final cell = HeatmapCell(
      cellId: 'A0',
      colorHex: '#9E9E9E',
      status: SearchAreaStatus.unscanned,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SearchAreaDetailSheet(cell: cell)),
      ),
    );

    await tester.tap(find.byKey(const Key('expand-confirmation-video')));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byTooltip('확대 영상 닫기'), findsOneWidget);
  });

  testWidgets('shows call connection and push-to-talk states', (tester) async {
    final cell = HeatmapCell(
      cellId: 'A0',
      colorHex: '#9E9E9E',
      status: SearchAreaStatus.unscanned,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SearchAreaDetailSheet(cell: cell)),
      ),
    );

    final connect = find.byKey(const Key('connect-survivor-call'));
    expect(connect, findsOneWidget);
    expect(find.text('통화 대기'), findsOneWidget);
    expect(find.text('통화 중'), findsNothing);

    await tester.ensureVisible(connect);
    await tester.tap(connect);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('연결 중…'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1200));
    expect(find.text('통화 중'), findsOneWidget);
    expect(find.byKey(const Key('continuous-voice-active')), findsOneWidget);
    expect(find.text('음성 전달 중'), findsOneWidget);
    expect(find.byKey(const Key('push-to-talk')), findsNothing);

    await tester.ensureVisible(find.text('눌러서 말하기'));
    await tester.tap(find.text('눌러서 말하기'));
    await tester.pump();
    expect(find.byKey(const Key('push-to-talk')), findsOneWidget);
    expect(find.byKey(const Key('push-to-talk-hint')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2600));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('push-to-talk-hint')), findsNothing);

    await tester.ensureVisible(find.byKey(const Key('push-to-talk')));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('push-to-talk'))),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('말하는 중'), findsOneWidget);
    await gesture.up();
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(const Key('push-to-talk')),
        matching: find.text('눌러서 말하기'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('통화 종료'));
    await tester.pump();
    expect(find.text('통화 종료됨'), findsOneWidget);
    expect(find.byKey(const Key('reconnect-survivor-call')), findsOneWidget);
    expect(find.text('다시 전화하기'), findsOneWidget);

    await tester.tap(find.byKey(const Key('reconnect-survivor-call')));
    await tester.pump();
    expect(find.text('연결 중…'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1200));
    expect(find.text('통화 중'), findsOneWidget);
  });

  testWidgets('offline demo does not request stored video', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: VideoReviewSection(cellId: 'A0', demoMode: true),
          ),
        ),
      ),
    );

    expect(find.textContaining('데모 모드'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('allows selecting every retained video bookmark', (tester) async {
    final bookmarks = [
      VideoBookmark(
        bookmarkId: 'newest',
        cellId: 'A0',
        triggeredAt: DateTime(2026, 8, 15, 14),
        frameCount: 1,
        complete: true,
      ),
      VideoBookmark(
        bookmarkId: 'earlier',
        cellId: 'A0',
        triggeredAt: DateTime(2026, 8, 15, 13),
        frameCount: 1,
        complete: true,
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VideoBookmarkHistory(
            bookmarks: bookmarks,
            baseUrl: 'http://localhost:8000',
          ),
        ),
      ),
    );

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('08/15 13:00').last);
    await tester.pumpAndSettle();

    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as NetworkImage).url, contains('/earlier/'));
  });
}
