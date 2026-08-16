import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/connection_badge.dart';
import '../../core/widgets/queue_chip.dart';
import '../../models/detection_event.dart';
import '../../models/drone_state.dart';
import '../../models/grid_cell.dart';
import '../detection/detection_sheet.dart';
import '../detection/providers/detection_log_provider.dart';
import '../log/log_screen.dart';
import '../log/providers/combined_log_provider.dart';
import '../settings/settings_screen.dart';
import 'providers/drones_provider.dart';
import 'providers/grid_provider.dart';
import 'providers/map_focus_provider.dart';
import 'providers/ws_providers.dart';
import 'widgets/heatmap_painter.dart';
import 'widgets/help_screen.dart';
import 'widgets/marker_layer.dart';
import 'widgets/offline_banner.dart';
import 'widgets/search_area_detail_sheet.dart';

enum _ControlMenuItem { log, help, settings }

/// 관제 화면 — 지도 중심의 현장 업무 화면.
class ControlScreen extends ConsumerStatefulWidget {
  const ControlScreen({super.key});

  @override
  ConsumerState<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends ConsumerState<ControlScreen> {
  final _mapController = MapController();
  bool _centeredOnFirstDrone = false;
  DetectionEvent? _activeDetection;
  String? _selectedCellId;

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  void _openDetectionPanel(DetectionEvent event) {
    setState(() => _activeDetection = event);
  }

  void _handleDetectionOutcome(DetectionOutcome outcome) {
    if (!mounted) return;
    if (outcome == DetectionOutcome.minimized) {
      setState(() => _activeDetection = null);
      return;
    }
    final queue = ref.read(pendingDetectionQueueProvider);
    setState(() => _activeDetection = queue.lastOrNull);
  }

  void _openSearchAreaDetail(LatLng point) {
    final grid = ref.read(gridDefProvider);
    final cellId = findContainingCellId(grid, point);
    if (cellId == null) return;
    setState(() => _selectedCellId = cellId);
  }

  @override
  Widget build(BuildContext context) {
    // Keep the operational timeline active while the control screen is open,
    // not only after the operator visits the log screen.
    ref.watch(combinedLogProvider);
    // Auto-pan to the first drone once telemetry starts arriving.
    ref.listen(dronesProvider, (previous, next) {
      if (!_centeredOnFirstDrone && next.isNotEmpty) {
        _centeredOnFirstDrone = true;
        _mapController.move(next.values.first.position, 15);
      }
    });

    // 새 탐지는 항상 스택의 최상단 상세로 열고, 기존 미처리 탐지는 아래의
    // 축약 알림으로 남긴다.
    ref.listen<List<DetectionEvent>>(pendingDetectionQueueProvider, (
      previous,
      next,
    ) {
      final added = next.length > (previous?.length ?? 0);
      if (added && next.isNotEmpty) {
        _openDetectionPanel(next.last);
      }
    });

    // 기록 화면의 "지도에서 보기"가 세팅하면 그 좌표로 팬 이동 후 요청을 비운다.
    ref.listen(mapFocusRequestProvider, (previous, next) {
      if (next != null) {
        _mapController.move(next, 16);
        Future.microtask(
          () => ref.read(mapFocusRequestProvider.notifier).state = null,
        );
      }
    });

    final activeDetection = _activeDetection;
    final selectedCellId = _selectedCellId;
    final pendingDetections = ref.watch(pendingDetectionQueueProvider);
    final locationLabels = ref.watch(gridLocationLabelProvider);
    final gridDefinition = ref.watch(gridDefProvider);
    return Scaffold(
      body: Column(
        children: [
          _OperationHeader(
            queueCount: ref.watch(
              pendingDetectionQueueProvider.select((q) => q.length),
            ),
            onQueueTap: () {
              final queue = ref.read(pendingDetectionQueueProvider);
              if (queue.isNotEmpty) _openDetectionPanel(queue.last);
            },
            onMenuSelected: (item) {
              final route = switch (item) {
                _ControlMenuItem.log => const LogScreen(),
                _ControlMenuItem.help => const HelpScreen(),
                _ControlMenuItem.settings => const SettingsScreen(),
              };
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => route));
            },
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => Stack(
                children: [
                  Positioned.fill(
                    child: FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: const LatLng(
                          37.5012,
                          127.0262,
                        ), // 강남↔신논현 중간
                        initialZoom: 15,
                        interactionOptions: const InteractionOptions(
                          flags: InteractiveFlag.all,
                        ),
                        onTap: (_, point) => _openSearchAreaDetail(point),
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.drone.control_app',
                        ),
                        const HeatmapPainterLayer(),
                        const DroneMarkerLayer(),
                      ],
                    ),
                  ),
                  const Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: OfflineBanner(),
                  ),
                  if (activeDetection != null)
                    Positioned(
                      top: AppSpacing.md,
                      right: AppSpacing.md,
                      width: 360,
                      child: _DetectionPanelStack(
                        maxHeight: constraints.maxHeight - AppSpacing.xl,
                        activeDetection: activeDetection,
                        pendingDetections: pendingDetections,
                        locationLabels: locationLabels,
                        gridDefinition: gridDefinition,
                        onDetectionTap: _openDetectionPanel,
                        onOutcome: _handleDetectionOutcome,
                      ),
                    ),
                  if (activeDetection == null && selectedCellId != null)
                    Positioned(
                      top: AppSpacing.md,
                      right: AppSpacing.md,
                      width: 360,
                      child: _FloatingMapPanel(
                        maxHeight: constraints.maxHeight - AppSpacing.xl,
                        child: LiveSearchAreaDetail(
                          key: ValueKey(selectedCellId),
                          cellId: selectedCellId,
                          onClose: () => setState(() => _selectedCellId = null),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetectionPanelStack extends StatelessWidget {
  const _DetectionPanelStack({
    required this.maxHeight,
    required this.activeDetection,
    required this.pendingDetections,
    required this.locationLabels,
    required this.gridDefinition,
    required this.onDetectionTap,
    required this.onOutcome,
  });

  final double maxHeight;
  final DetectionEvent activeDetection;
  final List<DetectionEvent> pendingDetections;
  final Map<String, String> locationLabels;
  final Map<String, CellBounds> gridDefinition;
  final ValueChanged<DetectionEvent> onDetectionTap;
  final ValueChanged<DetectionOutcome> onOutcome;

  @override
  Widget build(BuildContext context) {
    final previous = pendingDetections.reversed
        .where((event) => event.detectionId != activeDetection.detectionId)
        .take(2)
        .toList();
    final notificationHeight = previous.length * 60.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _FloatingMapPanel(
          maxHeight: maxHeight - notificationHeight,
          child: DetectionSheet(
            key: ValueKey(activeDetection.detectionId),
            event: activeDetection,
            showCloseButton: true,
            onOutcome: onOutcome,
          ),
        ),
        for (final event in previous) ...[
          const SizedBox(height: AppSpacing.sm),
          _DetectionNoticeCard(
            event: event,
            locationLabel: locationLabelForCell(
              cellId: event.cellId,
              labels: locationLabels,
              grid: gridDefinition,
            ),
            onTap: () => onDetectionTap(event),
          ),
        ],
      ],
    );
  }
}

class _DetectionNoticeCard extends StatelessWidget {
  const _DetectionNoticeCard({
    required this.event,
    required this.locationLabel,
    required this.onTap,
  });

  final DetectionEvent event;
  final String locationLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface,
    shape: RoundedRectangleBorder(
      side: const BorderSide(color: AppColors.border),
      borderRadius: BorderRadius.circular(2),
    ),
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              size: 18,
              color: AppColors.warning,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                locationLabel,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              _notificationAge(event.timestamp),
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    ),
  );
}

String _notificationAge(double timestampSeconds) {
  final timestamp = DateTime.fromMillisecondsSinceEpoch(
    (timestampSeconds * 1000).round(),
  );
  final elapsed = DateTime.now().difference(timestamp);
  if (elapsed.inMinutes < 1) return '방금 전';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes}분 전';
  return '${elapsed.inHours}시간 전';
}

class _FloatingMapPanel extends StatelessWidget {
  const _FloatingMapPanel({required this.maxHeight, required this.child});

  final double maxHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

class _OperationHeader extends ConsumerWidget {
  const _OperationHeader({
    required this.queueCount,
    required this.onQueueTap,
    required this.onMenuSelected,
  });

  final int queueCount;
  final VoidCallback onQueueTap;
  final ValueChanged<_ControlMenuItem> onMenuSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = ref.watch(wsConnectionProvider);
    final drones = ref.watch(dronesProvider).values.toList();
    final drone = drones.firstOrNull;
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
          _NavigationItem(
            label: '기록',
            onTap: () => onMenuSelected(_ControlMenuItem.log),
          ),
          _NavigationItem(
            label: '도움말',
            onTap: () => onMenuSelected(_ControlMenuItem.help),
          ),
          _NavigationItem(
            label: '설정',
            onTap: () => onMenuSelected(_ControlMenuItem.settings),
          ),
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
    if (activeDrone == null) {
      return const Text('드론 연결 대기 중');
    }
    return Row(
      children: [
        Text(
          '드론 ${activeDrone.droneId} · 배터리 ${activeDrone.battery}% · 고도 ${activeDrone.altitude.toStringAsFixed(0)}m',
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ],
    );
  }
}

class _NavigationItem extends StatelessWidget {
  const _NavigationItem({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
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
}
