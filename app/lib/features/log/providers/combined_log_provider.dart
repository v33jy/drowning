import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/severity.dart';
import '../../detection/providers/detection_log_provider.dart';
import '../models/log_entry.dart';
import 'drone_alert_provider.dart';

/// Single feed backing both 기록 tabs (전체/미확인) — detections and drone
/// health alerts merged and sorted newest-first, not two separate lists.
final combinedLogProvider = Provider<List<LogEntry>>((ref) {
  final detections = ref.watch(detectionLogProvider);
  final alerts = ref.watch(droneAlertProvider);

  final entries = [
    for (final d in detections)
      LogEntry(
        type: LogEntryType.detection,
        droneId: d.event.droneId,
        timestamp: DateTime.fromMillisecondsSinceEpoch((d.event.timestamp * 1000).round()),
        title: '탐지 발생 — 드론 #${d.event.droneId} · Cell ${d.event.cellId}',
        severity: switch (d.status) {
          DetectionStatus.pending => Severity.warning,
          DetectionStatus.rescued => Severity.ok,
          DetectionStatus.falseAlarm => Severity.offline,
        },
        detectionEvent: d.event,
        status: d.status,
      ),
    ...alerts,
  ]..sort((a, b) => b.timestamp.compareTo(a.timestamp));

  return entries;
});

final unresolvedLogProvider = Provider<List<LogEntry>>((ref) {
  return ref.watch(combinedLogProvider).where((e) => e.isUnresolved).toList();
});
