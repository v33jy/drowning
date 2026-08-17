import 'package:control_app/services/microphone_permission_guidance.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  test('일시적으로 거부된 권한은 재시도를 안내한다', () {
    final guidance = MicrophonePermissionGuidance.fromStatus(
      PermissionStatus.denied,
    );

    expect(guidance.recoveryAction, CallRecoveryAction.retry);
    expect(guidance.message, '통화하려면 마이크 권한이 필요합니다.');
  });

  test('영구 거부된 권한은 기기 설정 이동을 안내한다', () {
    final guidance = MicrophonePermissionGuidance.fromStatus(
      PermissionStatus.permanentlyDenied,
    );

    expect(guidance.recoveryAction, CallRecoveryAction.openMicrophoneSettings);
    expect(guidance.message, contains('기기 설정'));
  });
}
