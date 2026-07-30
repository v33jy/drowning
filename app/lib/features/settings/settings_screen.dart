import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/connection_badge.dart';
import '../control/providers/ws_providers.dart';

/// 설정 — 서버 주소는 배포 시 고정값(빌드 환경변수)이라 현장에서 바꿀 대상이
/// 아니므로 편집 UI를 두지 않는다. 읽기전용 시스템 정보만 보여준다.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = ref.watch(wsConnectionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        children: [
          const _GroupLabel('시스템 정보'),
          ListTile(
            title: const Text('서버 연결 상태'),
            trailing: ConnectionBadge(status: connection.value ?? ConnectionStatus.connecting),
          ),
          const ListTile(
            title: Text('버전'),
            trailing: Text('1.0.0', style: TextStyle(color: AppColors.textSecondary)),
          ),
        ],
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xs),
      child: Text(text, style: AppTypography.eyebrow(AppColors.textSecondary)),
    );
  }
}
