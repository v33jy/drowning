import 'package:flutter_test/flutter_test.dart';
import 'package:survivor_app/main.dart';

void main() {
  test('로컬 signaling URL을 만든다', () {
    expect(
      ServerConfig.ws('/survivors/listen'),
      'ws://localhost:8000/survivors/listen',
    );
  });
}
