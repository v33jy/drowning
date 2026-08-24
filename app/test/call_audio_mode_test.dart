import 'package:flutter_test/flutter_test.dart';
import 'package:control_app/services/call_service.dart';

void main() {
  test('통화하기와 눌러서 말하기가 마이크 송신 상태를 분리한다', () {
    final service = AudioModeTestCallService();

    service.setAudioMode(CallAudioMode.pushToTalk);
    expect(service.state.audioMode, CallAudioMode.pushToTalk);
    expect(service.state.isTransmitting, isFalse);

    service.startTransmitting();
    expect(service.state.isTransmitting, isTrue);
    service.stopTransmitting();
    expect(service.state.isTransmitting, isFalse);

    service.setAudioMode(CallAudioMode.call);
    expect(service.state.audioMode, CallAudioMode.call);
    expect(service.state.isTransmitting, isTrue);

    service.dispose();
  });
}

class AudioModeTestCallService extends CallService {
  AudioModeTestCallService() {
    state = const CallState(CallStatus.active, sessionId: 'test-call');
  }
}
