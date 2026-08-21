import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

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
    final connectionStatus = connection.value ?? ConnectionStatus.connecting;
    final visibleStatus =
        connectionStatus == ConnectionStatus.connected && drone == null
        ? ConnectionStatus.waitingForDrone
        : connectionStatus;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            height: 68,
            padding: const EdgeInsets.only(left: 14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
              boxShadow: [
                BoxShadow(
                  color: AppColors.navy.withValues(alpha: 0.13),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 42,
                  height: 42,
                  child: SvgPicture.asset(
                    'assets/images/drowning-drone-logo.svg',
                    fit: BoxFit.contain,
                    semanticsLabel: 'DROWNING 로고',
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DROWNING',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.navy,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.3,
                      ),
                    ),
                    Text(
                      '긴급 구조 통합관제',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.navy,
                        fontWeight: FontWeight.w800,
                        height: 1.05,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 18),
                Container(
                  width: 1,
                  height: 30,
                  color: AppColors.navy.withValues(alpha: 0.12),
                ),
                const SizedBox(width: 18),
                ConnectionBadge(status: visibleStatus),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _DroneStatus(drone: drone),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    QueueChip(count: queueCount, onTap: onQueueTap),
                    if (queueCount > 0) const SizedBox(width: AppSpacing.md),
                    _NavigationItem(label: '기록', onTap: onLogTap),
                    _NavigationItem(label: '도움말', onTap: onHelpTap),
                    _NavigationItem(
                      label: '설정',
                      onTap: onSettingsTap,
                      isLast: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
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
    if (activeDrone == null) return const SizedBox.shrink();
    return Text(
      '드론 ${activeDrone.droneId} · 배터리 ${activeDrone.battery}% · '
      '고도 ${activeDrone.altitude.toStringAsFixed(0)}m',
      style: Theme.of(context).textTheme.labelMedium,
    );
  }
}

class _NavigationItem extends StatelessWidget {
  const _NavigationItem({
    required this.label,
    required this.onTap,
    this.isLast = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool isLast;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: EdgeInsets.only(
        left: 14,
        right: isLast ? 24 : 14,
        top: 11,
        bottom: 11,
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.navy,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.1,
        ),
      ),
    ),
  );
}
