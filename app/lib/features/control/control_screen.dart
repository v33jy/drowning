import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_spacing.dart';
import '../../models/detection_event.dart';
import '../../models/grid_cell.dart';
import '../detection/detection_sheet.dart';
import '../detection/providers/detection_log_provider.dart';
import '../log/log_screen.dart';
import '../log/providers/combined_log_provider.dart';
import '../settings/settings_screen.dart';
import 'providers/drones_provider.dart';
import 'providers/grid_provider.dart';
import 'providers/map_focus_provider.dart';
import 'widgets/detection_panel_stack.dart';
import 'widgets/floating_map_panel.dart';
import 'widgets/heatmap_painter.dart';
import 'widgets/help_screen.dart';
import 'widgets/marker_layer.dart';
import 'widgets/offline_banner.dart';
import 'widgets/operation_header.dart';
import 'widgets/search_area_detail_sheet.dart';

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
          OperationHeader(
            queueCount: ref.watch(
              pendingDetectionQueueProvider.select((q) => q.length),
            ),
            onQueueTap: () {
              final queue = ref.read(pendingDetectionQueueProvider);
              if (queue.isNotEmpty) _openDetectionPanel(queue.last);
            },
            onLogTap: () => _openRoute(const LogScreen()),
            onHelpTap: () => _openRoute(const HelpScreen()),
            onSettingsTap: () => _openRoute(const SettingsScreen()),
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
                      child: DetectionPanelStack(
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
                      child: FloatingMapPanel(
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

  void _openRoute(Widget route) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => route));
  }
}
