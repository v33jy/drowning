import 'package:flutter_test/flutter_test.dart';
import 'package:control_app/models/heatmap_cell.dart';

void main() {
  test('parses search-area summary fields', () {
    final cell = HeatmapCell.fromJson({
      'cell_id': 'A0',
      'drone_id': 2,
      'rss_dbm': -58.0,
      'latest_rss_dbm': -55.0,
      'average_rss_dbm': -59.2,
      'peak_rss_dbm': -50.0,
      'sample_count': 4,
      'drone_count': 2,
      'strong_signal_count': 3,
      'color': '#F57C00',
      'status': 'needs_recheck',
      'status_reason': 'repeated_strong_signal',
      'last_updated': 1700000000.0,
    });

    expect(cell.status, SearchAreaStatus.needsRecheck);
    expect(cell.needsRecheck, isTrue);
    expect(cell.sampleCount, 4);
    expect(cell.droneCount, 2);
    expect(cell.lastUpdated, isNotNull);
  });

  test('maps pre-search-status active payloads to scanning', () {
    final cell = HeatmapCell.fromJson({
      'cell_id': 'A0',
      'color': '#1976D2',
      'status': 'active',
    });

    expect(cell.status, SearchAreaStatus.scanning);
    expect(cell.sampleCount, 0);
  });
}
