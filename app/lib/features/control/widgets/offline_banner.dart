import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../providers/drones_provider.dart';

/// Persistent, non-blocking banner — separate from [ConnectionBadge].
/// The badge says "the server link is fine"; this says "a specific drone's
/// telemetry went stale", which the badge alone can't distinguish.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lostDrones = ref.watch(
      dronesProvider.select(
        (drones) => drones.values.where((d) => d.status == 'lost').toList(),
      ),
    );
    if (lostDrones.isEmpty) return const SizedBox.shrink();

    final label = lostDrones.length == 1
        ? '드론 #${lostDrones.first.droneId} 신호 상실'
        : '드론 ${lostDrones.length}대 신호 상실';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      color: AppColors.surfaceSunken,
      child: Row(
        children: [
          const Icon(Icons.signal_wifi_off, size: 16, color: AppColors.offline),
          const SizedBox(width: AppSpacing.sm),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.offline,
            ),
          ),
        ],
      ),
    );
  }
}
