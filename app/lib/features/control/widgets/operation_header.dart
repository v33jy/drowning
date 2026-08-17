import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/connection_badge.dart';
import '../../../core/widgets/queue_chip.dart';
import '../../../models/drone_state.dart';
import '../providers/drones_provider.dart';
import '../providers/ws_providers.dart';

class OperationHeader extends ConsumerWidget {
  const OperationHeader({
    required this.queueCount,
    required this.onQueueTap,
    required this.onLogTap,
    required this.onHelpTap,
    required this.onSettingsTap,
    super.key,
  });

  final int queueCount;
  final VoidCallback onQueueTap;
  final VoidCallback onLogTap;
  final VoidCallback onHelpTap;
  final VoidCallback onSettingsTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = ref.watch(wsConnectionProvider);
    final drone = ref.watch(dronesProvider).values.firstOrNull;
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Text(
            '실시간 관제',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: AppColors.navy,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          ConnectionBadge(
            status: connection.value ?? ConnectionStatus.connecting,
          ),
          const SizedBox(width: AppSpacing.md),
          _DroneStatus(drone: drone),
          const Spacer(),
          QueueChip(count: queueCount, onTap: onQueueTap),
          if (queueCount > 0) const SizedBox(width: AppSpacing.md),
          _NavigationItem(label: '기록', onTap: onLogTap),
          _NavigationItem(label: '도움말', onTap: onHelpTap),
          _NavigationItem(label: '설정', onTap: onSettingsTap),
        ],
      ),
    );
  }
}

class _DroneStatus extends StatelessWidget {
  const _DroneStatus({required this.drone});

  final DroneState? drone;

  @override
  Widget build(BuildContext context) {
    final activeDrone = drone;
    if (activeDrone == null) return const Text('드론 연결 대기 중');
    return Text(
      '드론 ${activeDrone.droneId} · 배터리 ${activeDrone.batteryLabel} · '
      '고도 ${activeDrone.altitude.toStringAsFixed(0)}m',
      style: Theme.of(context).textTheme.labelMedium,
    );
  }
}

class _NavigationItem extends StatelessWidget {
  const _NavigationItem({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Center(
        child: Text(
          label,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ),
  );
}
