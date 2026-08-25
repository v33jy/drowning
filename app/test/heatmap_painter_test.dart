import 'package:control_app/features/control/widgets/heatmap_painter.dart';
import 'package:control_app/models/heatmap_cell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

HeatmapCell cell(SearchAreaStatus status, double score, {double? signal}) =>
    HeatmapCell(
      cellId: 'A0',
      colorHex: '#000000',
      status: status,
      candidateScore: score,
      rssDbm: signal,
    );

void main() {
  test('strongest measured signal is orange', () {
    expect(
      heatmapDisplayColor(cell(SearchAreaStatus.needsRecheck, 1)),
      const Color(0xFFF57C00),
    );
  });

  test('confirmed survivor is red regardless of score', () {
    expect(
      heatmapDisplayColor(cell(SearchAreaStatus.confirmed, 0.2)),
      const Color(0xFFD32F2F),
    );
  });

  test('unscanned area has no fill color', () {
    expect(
      heatmapDisplayColor(cell(SearchAreaStatus.unscanned, 0)),
      Colors.transparent,
    );
  });

  test('측정 셀은 신호 세기별 색상을 사용한다', () {
    expect(
      heatmapDisplayColor(cell(SearchAreaStatus.scanning, 0, signal: -90)),
      const Color(0xFF1565C0),
    );
    expect(
      heatmapDisplayColor(cell(SearchAreaStatus.scanning, 0, signal: -80)),
      const Color(0xFF00838F),
    );
    expect(
      heatmapDisplayColor(cell(SearchAreaStatus.scanning, 0, signal: -70)),
      const Color(0xFF2E7D32),
    );
    expect(
      heatmapDisplayColor(cell(SearchAreaStatus.scanning, 0, signal: -60)),
      const Color(0xFFFBC02D),
    );
  });
}
