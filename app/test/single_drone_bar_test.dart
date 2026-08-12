import 'package:control_app/features/control/data/ws_client.dart';
import 'package:control_app/features/control/providers/ws_providers.dart';
import 'package:control_app/features/control/widgets/drone_list_sheet.dart';
import 'package:control_app/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows one operational drone instead of a drone list', (
    tester,
  ) async {
    final client = WsClient();
    addTearDown(client.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [wsClientProvider.overrideWithValue(client)],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: Stack(children: [DroneListBar()])),
        ),
      ),
    );

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
    await tester.pump();

    expect(find.text('운용 드론 #1'), findsOneWidget);
    expect(find.textContaining('배터리 84%'), findsOneWidget);
    expect(find.text('드론 1대'), findsNothing);
  });
}
