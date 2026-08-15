import 'package:control_app/features/control/widgets/search_area_detail_sheet.dart';
import 'package:control_app/features/control/widgets/search_area_guidance.dart';
import 'package:control_app/models/heatmap_cell.dart';
import 'package:control_app/models/video_bookmark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:control_app/features/control/widgets/video_review_section.dart';

void main() {
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
    expect(guidance.action, contains('재수색'));
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

  testWidgets('shows reason and action before measurement counts', (
    tester,
  ) async {
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

    expect(find.text('수색 구역 G4'), findsOneWidget);
    expect(find.text('재확인 필요'), findsOneWidget);
    expect(find.textContaining('권장 조치:'), findsOneWidget);
    expect(find.text('측정 횟수'), findsOneWidget);
    expect(find.text('확인 드론'), findsOneWidget);
    expect(find.textContaining('위치를 확정하지 않습니다'), findsOneWidget);
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
