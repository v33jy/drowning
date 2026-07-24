import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/connection_badge.dart';
import '../../core/widgets/queue_chip.dart';
import '../../core/widgets/status_chip.dart';
import '../../core/widgets/severity.dart';
import '../../models/detection_event.dart';
import '../detection/detection_sheet.dart';
import '../detection/providers/detection_log_provider.dart';
import '../log/log_screen.dart';
import '../settings/settings_screen.dart';
import 'providers/drones_provider.dart';
import 'providers/map_focus_provider.dart';
import 'providers/ws_providers.dart';
import 'widgets/drone_list_sheet.dart';
import 'widgets/heatmap_painter.dart';
import 'widgets/marker_layer.dart';
import 'widgets/offline_banner.dart';

enum _ControlMenuItem { log, settings }

/// 관제 화면 — the app's sole home screen. 기록/설정 are reached via the
/// menu icon (pushed routes with their own back button), not bottom tabs.
class ControlScreen extends ConsumerStatefulWidget {
  const ControlScreen({super.key});

  @override
  ConsumerState<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends ConsumerState<ControlScreen> {
  final _mapController = MapController();
  bool _centeredOnFirstDrone = false;
  bool _detectionSheetOpen = false;

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  // 통화 중이든 그냥 최소화한 상태든, 시트가 열려 있는 동안엔 새 탐지가 끼어들지
  // 않는다 — 큐 칩 숫자만 늘어나고, 현재 시트가 끝나야 다음 걸 연다.
  Future<void> _openDetectionSheet(DetectionEvent event) async {
    setState(() => _detectionSheetOpen = true);
    final outcome = await showDetectionSheet(context, event);
    if (!mounted) return;
    setState(() => _detectionSheetOpen = false);
    if (outcome != DetectionOutcome.minimized) {
      final queue = ref.read(pendingDetectionQueueProvider);
      if (queue.isNotEmpty) _openDetectionSheet(queue.first);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Auto-pan to the first drone once telemetry starts arriving.
    ref.listen(dronesProvider, (previous, next) {
      if (!_centeredOnFirstDrone && next.isNotEmpty) {
        _centeredOnFirstDrone = true;
        _mapController.move(next.values.first.position, 15);
      }
    });

    // 큐가 "비어있음 → 있음"으로 바뀔 때만 자동으로 연다. 이미 최소화된 채로
    // 대기 중인 상태에서 새 탐지가 추가되는 건(길이만 증가) 자동으로 다시 열지
    // 않는다 — 큐 칩 숫자만 올라간다.
    ref.listen<List<DetectionEvent>>(pendingDetectionQueueProvider, (previous, next) {
      final wasEmpty = previous == null || previous.isEmpty;
      if (wasEmpty && next.isNotEmpty && !_detectionSheetOpen) {
        _openDetectionSheet(next.first);
      }
    });

    // 기록 화면의 "지도에서 보기"가 세팅하면 그 좌표로 팬 이동 후 요청을 비운다.
    ref.listen(mapFocusRequestProvider, (previous, next) {
      if (next != null) {
        _mapController.move(next, 16);
        Future.microtask(() => ref.read(mapFocusRequestProvider.notifier).state = null);
      }
    });

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: const MapOptions(
              initialCenter: LatLng(37.5012, 127.0262), // 강남↔신논현 중간
              initialZoom: 15,
              interactionOptions: InteractionOptions(flags: InteractiveFlag.all),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.drone.control_app',
              ),
              const HeatmapPainterLayer(),
              const DroneMarkerLayer(),
            ],
          ),
          const Positioned(top: 0, left: 0, right: 0, child: OfflineBanner()),
          Positioned(
            top: AppSpacing.md,
            left: AppSpacing.md,
            right: AppSpacing.md,
            child: Row(
              children: [
                Consumer(
                  builder: (context, ref, _) {
                    final status = ref.watch(wsConnectionProvider);
                    return ConnectionBadge(
                      status: status.value ?? ConnectionStatus.connecting,
                    );
                  },
                ),
                const SizedBox(width: AppSpacing.sm),
                Consumer(
                  builder: (context, ref, _) {
                    final count = ref.watch(dronesProvider.select((d) => d.length));
                    return StatusChip(severity: Severity.ok, label: '드론 $count대');
                  },
                ),
                const Spacer(),
                Consumer(
                  builder: (context, ref, _) {
                    final queueCount =
                        ref.watch(pendingDetectionQueueProvider.select((q) => q.length));
                    return QueueChip(
                      count: queueCount,
                      onTap: _detectionSheetOpen
                          ? null
                          : () {
                              final queue = ref.read(pendingDetectionQueueProvider);
                              if (queue.isNotEmpty) _openDetectionSheet(queue.first);
                            },
                    );
                  },
                ),
                const SizedBox(width: AppSpacing.sm),
                _ControlMenuButton(
                  onSelected: (item) {
                    final route = switch (item) {
                      _ControlMenuItem.log => const LogScreen(),
                      _ControlMenuItem.settings => const SettingsScreen(),
                    };
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => route));
                  },
                ),
              ],
            ),
          ),
          const DroneListBar(),
        ],
      ),
    );
  }
}

class _ControlMenuButton extends StatelessWidget {
  const _ControlMenuButton({required this.onSelected});

  final ValueChanged<_ControlMenuItem> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.surface,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 6, offset: const Offset(0, 1)),
        ],
      ),
      child: PopupMenuButton<_ControlMenuItem>(
        tooltip: '메뉴',
        padding: EdgeInsets.zero,
        icon: const Icon(Icons.menu_outlined, color: AppColors.textPrimary, size: 20),
        offset: const Offset(0, AppSpacing.xl),
        onSelected: onSelected,
        itemBuilder: (context) => const [
          PopupMenuItem(
            value: _ControlMenuItem.log,
            child: _MenuRow(icon: Icons.list_alt_outlined, label: '기록'),
          ),
          PopupMenuItem(
            value: _ControlMenuItem.settings,
            child: _MenuRow(icon: Icons.settings_outlined, label: '설정'),
          ),
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.textSecondary),
        const SizedBox(width: AppSpacing.md),
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}
