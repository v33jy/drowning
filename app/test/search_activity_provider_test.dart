import 'package:control_app/features/control/data/ws_client.dart';
import 'package:control_app/features/control/providers/ws_providers.dart';
import 'package:control_app/features/log/models/log_entry.dart';
import 'package:control_app/features/log/providers/combined_log_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'records search start and recheck area as operational activities',
    () async {
      final client = WsClient();
      final container = ProviderContainer(
        overrides: [wsClientProvider.overrideWithValue(client)],
      );
      addTearDown(container.dispose);
      addTearDown(client.dispose);

      container.read(combinedLogProvider);
      client.emitDemo('init', {
        'drones': [
          {
            'drone_id': 1,
            'lat': 37.5,
            'lng': 127.02,
            'altitude': 50.0,
            'battery': 84,
            'status': 'active',
            'cell_id': 'A0',
          },
        ],
        'heatmap': <dynamic>[],
      });
      await Future<void>.delayed(Duration.zero);

      client.emitDemo('heatmap_update', [
        {
          'cell_id': 'A0',
          'drone_id': 1,
          'rss_dbm': -55.0,
          'color': '#F57C00',
          'status': 'needs_recheck',
          'status_reason': 'repeated_strong_signal',
        },
      ]);
      await Future<void>.delayed(Duration.zero);

      final activities = container
          .read(combinedLogProvider)
          .where((entry) => entry.type == LogEntryType.activity)
          .toList();
      expect(
        activities.map((entry) => entry.activityKind),
        containsAll([
          LogActivityKind.searchStarted,
          LogActivityKind.areaNeedsRecheck,
        ]),
      );
    },
  );
}
