import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../config.dart';
import '../../core/theme/app_spacing.dart';
import '../../models/detection_event.dart';
import '../../models/grid_cell.dart';
import '../../services/call_service.dart';
import '../detection/detection_sheet.dart';
import '../detection/providers/detection_log_provider.dart';
import '../log/log_screen.dart';
import '../log/providers/combined_log_provider.dart';
import '../settings/settings_screen.dart';
import 'candidate_api.dart';
import 'detection_panel_selection.dart';
import 'operational_section.dart';
import 'providers/drones_provider.dart';
import 'providers/grid_provider.dart';
import 'providers/heatmap_provider.dart';
import 'providers/map_focus_provider.dart';
import 'widgets/detection_panel_stack.dart';
import 'widgets/floating_map_panel.dart';
import 'widgets/heatmap_painter.dart';
import 'widgets/candidate_route_layer.dart';
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
  static const _defaultSearchPanelWidth = 440.0;
  static const _defaultSearchPanelHeight = 480.0;
  static const _defaultDetectionPanelHeight = 760.0;
  static const _minimumSearchPanelExtent = 320.0;
  static const _mapOverlayTop = 92.0;
  static const _mapOverlayVerticalInset = 108.0;

  final _mapController = MapController();
  bool _centeredOnFirstDrone = false;
  final Set<String> _openedCandidateCells = {};
  DetectionEvent? _activeDetection;
  DetectionStatus _activeDetectionStatus = DetectionStatus.pending;
  String? _selectedCellId;
  double _searchPanelWidth = _defaultSearchPanelWidth;
  double _searchPanelHeight = _defaultSearchPanelHeight;
  double _detectionPanelWidth = _defaultSearchPanelWidth;
  double _detectionPanelHeight = _defaultDetectionPanelHeight;

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  void _openDetectionPanel(DetectionEvent event) {
    final pendingDetections = ref.read(pendingDetectionQueueProvider);
    final selected = pendingDetections.isEmpty
        ? event
        : selectDetectionForDisplay(
            pendingDetections: pendingDetections,
            callState: ref.read(callServiceProvider),
            preferredDetection: event,
          );
    _showDetection(selected);
  }

  void _showDetection(
    DetectionEvent event, {
    DetectionStatus status = DetectionStatus.pending,
  }) => setState(() {
    _selectedCellId = null;
    _activeDetection = event;
    _activeDetectionStatus = status;
  });

  void _showSearchArea(String cellId) => setState(() {
    _activeDetection = null;
    _selectedCellId = cellId;
  });

  void _closeMapPanels() => setState(() {
    _activeDetection = null;
    _selectedCellId = null;
  });

  void _handleDetectionOutcome(DetectionOutcome outcome) {
    unawaited(_applyDetectionOutcome(outcome));
  }

  Future<void> _applyDetectionOutcome(DetectionOutcome outcome) async {
    if (!mounted) return;
    final cellId = _activeDetection?.cellId;
    if (cellId != null && outcome != DetectionOutcome.minimized) {
      final reviewOutcome = outcome == DetectionOutcome.falseAlarm
          ? 'false_alarm'
          : 'survivor_confirmed';
      final recorded = await _reviewCandidate(cellId, reviewOutcome);
      if (!recorded) {
        final detectionId = _activeDetection?.detectionId;
        if (detectionId != null) {
          ref
              .read(detectionLogProvider.notifier)
              .resolve(detectionId, DetectionStatus.pending);
        }
        if (mounted) {
          setState(() => _activeDetectionStatus = DetectionStatus.pending);
        }
        return;
      }
      if (!mounted) return;
    }
    if (outcome == DetectionOutcome.minimized) {
      _closeMapPanels();
      return;
    }
    if (outcome == DetectionOutcome.rescued) {
      setState(() => _activeDetectionStatus = DetectionStatus.rescued);
      return;
    }
    final queue = ref.read(pendingDetectionQueueProvider);
    final next = queue.lastOrNull;
    if (next == null) {
      _closeMapPanels();
    } else {
      _showDetection(next);
    }
  }

  Future<bool> _reviewCandidate(String cellId, String outcome) async {
    try {
      await reviewCandidateRequest(cellId: cellId, outcome: outcome);
      return true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('후보 처리에 실패했습니다. 다시 시도해 주세요.')),
        );
      }
      return false;
    }
  }

  Future<void> _openCandidateOnArrival(String cellId, int droneId) async {
    if (_openedCandidateCells.contains(cellId)) return;
    final cell = ref.read(heatmapProvider)[cellId];
    if (cell == null || !cell.needsRecheck) return;
    _openedCandidateCells.add(cellId);
    try {
      await reportCandidateDetection(
        droneId: droneId,
        cellId: cellId,
        signal: cell.rssDbm ?? cell.latestRssDbm ?? -65.0,
        streamUrl: Config.videoWhepUrl,
      );
    } catch (_) {
      _openedCandidateCells.remove(cellId);
    }
  }

  void _openSearchAreaDetail(LatLng point) {
    final grid = ref.read(gridDefProvider);
    final cellId = findContainingCellId(grid, point);
    if (cellId == null) return;
    _showSearchArea(cellId);
  }

  ({double maxWidth, double maxHeight, double minWidth, double minHeight})
  _panelBounds(BoxConstraints constraints) {
    final maxWidth = constraints.maxWidth - AppSpacing.md * 2;
    final maxHeight = constraints.maxHeight - _mapOverlayVerticalInset;
    return (
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      minWidth: math.min(maxWidth, _minimumSearchPanelExtent),
      minHeight: math.min(maxHeight, _minimumSearchPanelExtent),
    );
  }

  Widget _buildResizableSearchPanel(
    BoxConstraints constraints,
    String selectedCellId,
  ) {
    final bounds = _panelBounds(constraints);
    final panelWidth = _searchPanelWidth
        .clamp(bounds.minWidth, bounds.maxWidth)
        .toDouble();
    final panelHeight = _searchPanelHeight
        .clamp(bounds.minHeight, bounds.maxHeight)
        .toDouble();
    final widthScale = panelWidth / _defaultSearchPanelWidth;
    final heightScale = panelHeight / _defaultSearchPanelHeight;
    final textScale = math
        .max(widthScale, heightScale)
        .clamp(0.9, 1.3)
        .toDouble();

    return Positioned(
      top: _mapOverlayTop,
      right: AppSpacing.md,
      width: panelWidth,
      child: FloatingMapPanel(
        maxHeight: panelHeight,
        onResize: (details) => setState(() {
          _searchPanelWidth = (_searchPanelWidth - details.delta.dx)
              .clamp(bounds.minWidth, bounds.maxWidth)
              .toDouble();
          _searchPanelHeight = (_searchPanelHeight + details.delta.dy)
              .clamp(bounds.minHeight, bounds.maxHeight)
              .toDouble();
        }),
        child: MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: LiveSearchAreaDetail(
            key: ValueKey(selectedCellId),
            cellId: selectedCellId,
            onClose: _closeMapPanels,
          ),
        ),
      ),
    );
  }

  Widget _buildResizableDetectionPanel(
    BoxConstraints constraints,
    DetectionEvent activeDetection,
    List<DetectionEvent> pendingDetections,
    Map<String, String> locationLabels,
    Map<String, CellBounds> gridDefinition,
  ) {
    final bounds = _panelBounds(constraints);
    final panelWidth = _detectionPanelWidth
        .clamp(bounds.minWidth, bounds.maxWidth)
        .toDouble();
    final panelHeight = _detectionPanelHeight
        .clamp(bounds.minHeight, bounds.maxHeight)
        .toDouble();
    final widthScale = panelWidth / _defaultSearchPanelWidth;
    final heightScale = panelHeight / _defaultDetectionPanelHeight;
    final textScale = math
        .max(widthScale, heightScale)
        .clamp(0.9, 1.3)
        .toDouble();

    return Positioned(
      top: _mapOverlayTop,
      right: AppSpacing.md,
      width: panelWidth,
      child: MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: DetectionPanelStack(
          maxHeight: panelHeight,
          activeDetection: activeDetection,
          activeDetectionStatus: _activeDetectionStatus,
          pendingDetections: pendingDetections,
          locationLabels: locationLabels,
          gridDefinition: gridDefinition,
          onDetectionTap: _openDetectionPanel,
          onOutcome: _handleDetectionOutcome,
          onResize: (details) => setState(() {
            _detectionPanelWidth = (_detectionPanelWidth - details.delta.dx)
                .clamp(bounds.minWidth, bounds.maxWidth)
                .toDouble();
            _detectionPanelHeight = (_detectionPanelHeight + details.delta.dy)
                .clamp(bounds.minHeight, bounds.maxHeight)
                .toDouble();
          }),
        ),
      ),
    );
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
      for (final drone in next.values) {
        final previousCell = previous?[drone.droneId]?.cellId;
        if (drone.cellId != null && drone.cellId != previousCell) {
          unawaited(_openCandidateOnArrival(drone.cellId!, drone.droneId));
        }
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
    ref.listen(detectionFocusRequestProvider, (previous, next) {
      if (next != null) {
        _showDetection(next.event, status: next.status);
        Future.microtask(
          () => ref.read(detectionFocusRequestProvider.notifier).state = null,
        );
      }
    });

    final activeDetection = _activeDetection;
    final selectedCellId = _selectedCellId;
    final pendingDetections = ref.watch(pendingDetectionQueueProvider);
    final locationLabels = ref.watch(gridLocationLabelProvider);
    final gridDefinition = ref.watch(gridDefProvider);
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) => Stack(
                children: [
                  Positioned.fill(
                    child: FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: const LatLng(37.5012, 127.0262),
                        initialZoom: 15,
                        interactionOptions: const InteractionOptions(
                          flags: InteractiveFlag.all,
                        ),
                        onTap: (_, point) => _openSearchAreaDetail(point),
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                          userAgentPackageName: 'com.drone.control_app',
                        ),
                        const HeatmapLayer(),
                        CandidateRouteLayer(
                          highlightedCellId: activeDetection?.cellId,
                        ),
                        const DroneMarkerLayer(),
                        RichAttributionWidget(
                          attributions: [
                            TextSourceAttribution(
                              '© Esri, Maxar, Earthstar Geographics',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Positioned(
                    top: _mapOverlayTop,
                    left: 16,
                    right: 16,
                    child: OfflineBanner(),
                  ),
                  if (activeDetection != null)
                    _buildResizableDetectionPanel(
                      constraints,
                      activeDetection,
                      pendingDetections,
                      locationLabels,
                      gridDefinition,
                    ),
                  if (activeDetection == null && selectedCellId != null)
                    _buildResizableSearchPanel(constraints, selectedCellId),
                ],
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: OperationHeader(
                onHomeTap: () {},
                queueCount: ref.watch(
                  pendingDetectionQueueProvider.select((q) => q.length),
                ),
                onQueueTap: () {
                  final queue = ref.read(pendingDetectionQueueProvider);
                  if (queue.isNotEmpty) _openDetectionPanel(queue.last);
                },
                onLogTap: () => _openSection(OperationalSection.log),
                onHelpTap: () => _openSection(OperationalSection.help),
                onSettingsTap: () => _openSection(OperationalSection.settings),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openSection(OperationalSection section) {
    if (section == OperationalSection.control) {
      Navigator.of(context).pop();
      return;
    }
    final route = switch (section) {
      OperationalSection.log => LogScreen(
        onNavigate: _openSection,
        onQueueTap: _openQueueFromSection,
      ),
      OperationalSection.help => HelpScreen(
        onNavigate: _openSection,
        onQueueTap: _openQueueFromSection,
      ),
      OperationalSection.settings => SettingsScreen(
        onNavigate: _openSection,
        onQueueTap: _openQueueFromSection,
      ),
      OperationalSection.control => throw StateError('handled above'),
    };
    final pageRoute = PageRouteBuilder<void>(
      pageBuilder: (_, _, _) => route,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
    );
    final controlIsVisible = ModalRoute.of(context)?.isCurrent ?? true;
    if (!controlIsVisible) {
      Navigator.of(context).pushReplacement(pageRoute);
    } else {
      Navigator.of(context).push(pageRoute);
    }
  }

  void _openQueueFromSection() {
    final queue = ref.read(pendingDetectionQueueProvider);
    if (queue.isNotEmpty) _openDetectionPanel(queue.last);
    Navigator.of(context).pop();
  }
}
