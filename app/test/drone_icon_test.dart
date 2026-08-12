import 'package:control_app/features/control/widgets/drone_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
