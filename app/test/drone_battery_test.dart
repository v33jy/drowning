import 'package:control_app/features/control/widgets/marker_layer.dart';
import 'package:control_app/models/drone_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('unknown battery is parsed and displayed explicitly', () {
    final drone = DroneState.fromJson({
      'drone_id': 1,
      'lat': 37.5012,
      'lng': 127.0324,
      'altitude': 12.3,
      'battery': null,
      'status': 'active',
      'cell_id': 'A1',
    });

    expect(drone.battery, isNull);
    expect(drone.batteryLabel, '—');
    expect(droneStatusLabel(drone), '배터리 미확인');
  });

  test('lost status takes precedence over unknown battery', () {
    final drone = DroneState(
      droneId: 1,
      lat: 37.5012,
      lng: 127.0324,
      altitude: 12.3,
      battery: null,
      status: 'lost',
    );

    expect(droneStatusLabel(drone), 'Offline');
  });
}
