import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/connection_badge.dart';
import '../../core/widgets/liquid_page_components.dart';
import '../control/providers/ws_providers.dart';

/// 현장에서 확인할 필요가 있는 최소한의 관제 상태만 보여준다.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = ref.watch(wsConnectionProvider);
    final status = connection.value ?? ConnectionStatus.connecting;
    final connected = status == ConnectionStatus.connected;

    return Scaffold(
      backgroundColor: const Color(0xFFE8EEF5),
      body: Stack(
        children: [
          const Positioned.fill(child: LiquidPageBackdrop()),
          SafeArea(
            child: Column(
              children: [
                const NavyPageHeader(title: '설정'),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 22, 24, 32),
                    children: [
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1040),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _SystemHealthCard(
                                status: status,
                                connected: connected,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SystemHealthCard extends StatelessWidget {
  const _SystemHealthCard({required this.status, required this.connected});
  final ConnectionStatus status;
  final bool connected;
  @override
  Widget build(BuildContext context) => LiquidGlassPanel(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: (connected ? AppColors.success : AppColors.warning)
                  .withValues(alpha: .12),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              connected ? Icons.cloud_done_outlined : Icons.sync_rounded,
              color: connected ? AppColors.success : AppColors.warning,
              size: 28,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '관제 연결 상태',
                  style: AppTypography.eyebrow(AppColors.textSecondary),
                ),
                const SizedBox(height: 5),
                Text(
                  connected ? '모든 시스템 정상' : '연결 상태 확인 중',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  connected
                      ? '현장 데이터가 실시간으로 수신되고 있습니다.'
                      : '서버 연결을 자동으로 재시도하고 있습니다.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          ConnectionBadge(status: status),
        ],
      ),
    ),
  );
}
