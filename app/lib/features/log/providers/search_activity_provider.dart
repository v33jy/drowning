import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/severity.dart';
import '../../../models/drone_state.dart';
import '../../../services/call_service.dart';
import '../../control/providers/drones_provider.dart';
import '../../control/providers/heatmap_provider.dart';
import '../../detection/providers/detection_log_provider.dart';
import '../models/log_entry.dart';

/// Records operator-relevant state transitions rather than every telemetry or
/// RSS sample. This keeps the log useful as a search timeline.
class SearchActivityNotifier extends Notifier<List<LogEntry>> {
  bool _searchStarted = false;
  bool _disposed = false;

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
            '재확인 필요 구역 발생 — ${entry.key}',
            Severity.warning,
          );
        }
      }
    });

    ref.listen(callServiceProvider, (previous, next) {
      if (previous?.status == next.status) return;
      switch (next.status) {
        case CallStatus.connecting:
          _append(
            LogActivityKind.callConnecting,
            _currentDroneId,
            '음성 연결 시도',
            Severity.warning,
          );
        case CallStatus.active:
          _append(
            LogActivityKind.callConnected,
            _currentDroneId,
            '음성 연결됨',
            Severity.ok,
          );
        case CallStatus.reconnecting:
          _append(
            LogActivityKind.callConnecting,
            _currentDroneId,
            '음성 연결 끊김 · 자동 재연결 중',
            Severity.warning,
          );
        case CallStatus.disconnected:
          _append(
            LogActivityKind.callEnded,
            _currentDroneId,
            '음성 연결 실패 · 수동 재시도 필요',
            Severity.offline,
          );
        case CallStatus.idle:
          if (previous != null &&
              previous.status != CallStatus.idle &&
              previous.status != CallStatus.disconnected) {
            _append(
              LogActivityKind.callEnded,
              _currentDroneId,
              '음성 연결 종료',
              Severity.offline,
            );
          }
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
            '$label — 구역 ${entry.event.cellId}',
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
      '수색 시작 — 운용 드론 #${drone.droneId} 연결',
      Severity.ok,
    );
  }

  int get _currentDroneId => ref.read(dronesProvider).keys.firstOrNull ?? 1;

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
