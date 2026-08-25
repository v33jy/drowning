import 'package:control_app/features/control/widgets/candidate_route_layer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('후보 번호는 지도에서 보이는 셀 크기와 함께 커진다', () {
    expect(candidateMarkerDiameterForCellSide(30), closeTo(21.6, 0.001));
    expect(
      candidateMarkerDiameterForCellSide(60),
      greaterThan(candidateMarkerDiameterForCellSide(30)),
    );
    expect(candidateMarkerDiameterForCellSide(5), 18);
    expect(candidateMarkerDiameterForCellSide(200), 96);
  });
}
