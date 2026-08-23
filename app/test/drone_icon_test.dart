import 'package:control_app/features/control/widgets/drone_icon.dart';
import 'package:control_app/features/control/widgets/marker_layer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('scales map drone markers with zoom within safe bounds', () {
    expect(droneMarkerScale(15), 1);
    expect(droneMarkerScale(17), greaterThan(droneMarkerScale(15)));
    expect(droneMarkerScale(30), 1.8);
    expect(droneMarkerScale(0), 0.75);
  });

  testWidgets('renders a dedicated drone marker glyph', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: DroneIcon(color: Colors.blue)),
      ),
    );

    expect(find.byType(DroneIcon), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.byIcon(Icons.airplanemode_active), findsNothing);
  });
}
