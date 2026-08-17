import 'package:control_app/services/call_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  test('설정에서 마이크 권한을 허용하면 재시도 가능한 상태가 된다', () async {
    final service = PermissionTestCallService(PermissionStatus.granted);

    final shouldRetry = await service.refreshMicrophonePermission();

    expect(shouldRetry, isTrue);
    expect(service.state.canRetry, isTrue);
    expect(service.state.requiresMicrophoneSettings, isFalse);
  });

  test('마이크 권한이 여전히 거부 상태면 설정 안내를 유지한다', () async {
    final service = PermissionTestCallService(PermissionStatus.denied);

    final shouldRetry = await service.refreshMicrophonePermission();

    expect(shouldRetry, isFalse);
    expect(service.state.requiresMicrophoneSettings, isTrue);
  });
}

class PermissionTestCallService extends CallService {
  PermissionTestCallService(PermissionStatus permissionStatus)
    : super(microphonePermissionStatus: () async => permissionStatus) {
    state = const CallState(
      CallStatus.disconnected,
      sessionId: 'test-call',
      recoveryAction: CallRecoveryAction.openMicrophoneSettings,
    );
  }
}
