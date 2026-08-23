import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/severity.dart';
import '../../../models/drone_state.dart';
import '../../../services/call_service.dart';
import '../../control/providers/drones_provider.dart';
import '../../control/providers/heatmap_provider.dart';
import '../../control/providers/grid_provider.dart';
import '../../detection/providers/detection_log_provider.dart';
import '../models/log_entry.dart';
import 'call_activity_recorder.dart';

/// Records operator-relevant state transitions rather than every telemetry or
/// RSS sample. This keeps the log useful as a search timeline.
class SearchActivityNotifier extends Notifier<List<LogEntry>> {
  bool _searchStarted = false;
  bool _disposed = false;
  final _callRecorder = CallActivityRecorder();

  @override
  List<LogEntry> build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    Future.microtask(() {
      if (_disposed) return;
      _recordSearchStart(ref.read(dronesProvider));
    });

    ref.listen(dronesProvider, (previous, next) {
      _recordSearchStart(next);
    });

    ref.listen(heatmapProvider, (previous, next) {
      for (final entry in next.entries) {
        final wasRecheck = previous?[entry.key]?.needsRecheck ?? false;
        if (entry.value.needsRecheck && !wasRecheck) {
          _append(
            LogActivityKind.areaNeedsRecheck,
            entry.value.droneId ?? _currentDroneId,
            '재확인 필요 — ${_locationLabel(entry.key)}',
            Severity.warning,
          );
        }
      }
    });

    ref.listen(callServiceProvider, (previous, next) {
      final entries = _callRecorder.recordTransition(
        previous: previous,
        next: next,
        timestamp: DateTime.now(),
      );
      if (entries.isNotEmpty) {
        state = [...state, ...entries.map(_callLogEntry)];
      }
    });

    ref.listen(detectionLogProvider, (previous, next) {
      final previousStatuses = {
        for (final entry in previous ?? const <DetectionLogEntry>[])
          entry.event.detectionId: entry.status,
      };
      for (final entry in next) {
        final before = previousStatuses[entry.event.detectionId];
        if (before == DetectionStatus.pending && entry.status != before) {
          final label = entry.status == DetectionStatus.rescued
              ? '구조 완료 처리'
              : '오탐 처리';
          _append(
            LogActivityKind.detectionResolved,
            entry.event.droneId,
            '$label — ${_locationLabel(entry.event.cellId)}',
            entry.status == DetectionStatus.rescued
                ? Severity.ok
                : Severity.offline,
          );
        }
      }
    });

    return [];
  }

  void _recordSearchStart(Map<int, DroneState> drones) {
    if (_searchStarted || drones.isEmpty) return;
    _searchStarted = true;
    final drone = drones.values.first;
    _append(
      LogActivityKind.searchStarted,
      drone.droneId,
      '수색 시작 — 드론 #${drone.droneId} 운용 시작',
      Severity.ok,
    );
  }

  int get _currentDroneId => ref.read(dronesProvider).keys.firstOrNull ?? 1;

  String _locationLabel(String cellId) => locationLabelForCell(
    cellId: cellId,
    labels: ref.read(gridLocationLabelProvider),
    grid: ref.read(gridDefProvider),
  );

  LogEntry _callLogEntry(CallActivityRecord record) => LogEntry(
    type: LogEntryType.activity,
    activityKind: record.kind,
    droneId: _currentDroneId,
    timestamp: record.timestamp,
    title: record.title,
    severity: record.severity,
    callDetails: record.details,
  );

  void _append(
    LogActivityKind kind,
    int droneId,
    String title,
    Severity severity,
  ) {
    state = [
      ...state,
      LogEntry(
        type: LogEntryType.activity,
        activityKind: kind,
        droneId: droneId,
        timestamp: DateTime.now(),
        title: title,
        severity: severity,
      ),
    ];
  }
}

final searchActivityProvider =
    NotifierProvider<SearchActivityNotifier, List<LogEntry>>(
      SearchActivityNotifier.new,
    );
