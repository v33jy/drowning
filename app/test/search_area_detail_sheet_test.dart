import 'package:control_app/features/control/widgets/search_area_detail_sheet.dart';
import 'package:control_app/features/control/widgets/search_area_guidance.dart';
import 'package:control_app/features/control/providers/grid_provider.dart';
import 'package:control_app/features/control/data/demo_feed.dart';
import 'package:control_app/models/grid_cell.dart';
import 'package:control_app/models/heatmap_cell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

    expect(guidance.statusLabel, '요구조자 후보');
    expect(guidance.reason, contains('반복적으로 측정'));
    expect(guidance.action, contains('현장 영상'));
  });

  test('측정 셀을 신호 세기별 라벨로 구분한다', () {
    SearchAreaGuidance guidance(double signal) => SearchAreaGuidance.fromCell(
      HeatmapCell(
        cellId: 'A0',
        colorHex: '#000000',
        status: SearchAreaStatus.scanning,
        rssDbm: signal,
      ),
    );

    expect(guidance(-90).statusLabel, '신호 매우 약함');
    expect(guidance(-80).statusLabel, '신호 약함');
    expect(guidance(-70).statusLabel, '신호 보통');
    expect(guidance(-60).statusLabel, '신호 강함');
    expect(guidance(-60).reason, isNot(contains('RSSI')));
  });

  test('falls back to status guidance for a missing legacy reason', () {
    final cell = HeatmapCell(
      cellId: 'A0',
      colorHex: '#1976D2',
      status: SearchAreaStatus.scanning,
    );

    final guidance = SearchAreaGuidance.fromCell(cell);

    expect(guidance.statusLabel, '신호 매우 약함');
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
      expect(find.text('요구조자 후보'), findsOneWidget);
      expect(find.text('판단 이유'), findsNothing);
      expect(find.textContaining('다음 행동 지침:'), findsNothing);
      expect(find.textContaining('번호 순서대로 방문'), findsOneWidget);
      expect(find.text('측정 횟수'), findsNothing);
      expect(find.text('확인 드론'), findsNothing);
      expect(find.textContaining('위치를 확정하지 않습니다'), findsNothing);
    },
  );

  testWidgets('does not duplicate the saved video with a mock preview', (
    tester,
  ) async {
    final cell = HeatmapCell(
      cellId: 'A0',
      colorHex: '#9E9E9E',
      status: SearchAreaStatus.unscanned,
      lastUpdated: DateTime.now().toUtc(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SearchAreaDetailSheet(cell: cell)),
      ),
    );

    expect(find.byKey(const Key('expand-confirmation-video')), findsNothing);
  });

  testWidgets('does not show survivor call controls in a cell detail', (
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

    expect(find.text('요구조자 전화'), findsNothing);
    expect(find.byKey(const Key('connect-survivor-call')), findsNothing);
  });
}
