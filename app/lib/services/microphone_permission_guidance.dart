import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

enum CallRecoveryAction { retry, openMicrophoneSettings }

@immutable
class MicrophonePermissionGuidance {
  const MicrophonePermissionGuidance({
    required this.message,
    required this.recoveryAction,
  });

  factory MicrophonePermissionGuidance.fromStatus(PermissionStatus status) {
    if (status.isPermanentlyDenied) {
      return const MicrophonePermissionGuidance(
        message: '마이크 권한이 꺼져 있습니다. 기기 설정에서 권한을 허용하세요.',
        recoveryAction: CallRecoveryAction.openMicrophoneSettings,
      );
    }

    return const MicrophonePermissionGuidance(
      message: '통화하려면 마이크 권한이 필요합니다.',
      recoveryAction: CallRecoveryAction.retry,
    );
  }

  final String message;
  final CallRecoveryAction recoveryAction;
}
