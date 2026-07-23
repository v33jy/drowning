import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/severity.dart';
import '../../control/providers/drones_provider.dart';
import '../models/log_entry.dart';

/// Derives 배터리 부족 / 신호 상실 alerts from telemetry transitions — fires
/// once when a drone *crosses into* a bad state, not on every subsequent
/// telemetry tick while it stays there.
class DroneAlertNotifier extends Notifier<List<LogEntry>> {
  final Map<int, bool> _lowBatteryFlags = {};
  final Map<int, bool> _lostFlags = {};

  @override
  List<LogEntry> build() {
    ref.listen(dronesProvider, (previous, next) {
      for (final drone in next.values) {
        final wasLow = _lowBatteryFlags[drone.droneId] ?? false;
        final isLow = drone.battery <= 20;
        if (isLow && !wasLow) {
          state = [
            ...state,
            LogEntry(
              type: LogEntryType.batteryLow,
              droneId: drone.droneId,
              timestamp: DateTime.now(),
              title: '배터리 부족 — 드론 #${drone.droneId} (${drone.battery}%)',
              severity: Severity.warning,
            ),
          ];
        }
        _lowBatteryFlags[drone.droneId] = isLow;

        final wasLost = _lostFlags[drone.droneId] ?? false;
        final isLost = drone.status == 'lost';
        if (isLost && !wasLost) {
          state = [
            ...state,
            LogEntry(
              type: LogEntryType.signalLost,
              droneId: drone.droneId,
              timestamp: DateTime.now(),
              title: '신호 상실 — 드론 #${drone.droneId}',
              severity: Severity.danger,
            ),
          ];
        }
        _lostFlags[drone.droneId] = isLost;
      }
    });
    // No fireImmediately: writing to `state` synchronously here would run
    // before build() returns, which Riverpod rejects ("uninitialized
    // provider") — and it happened on every boot, since battery already
    // starts <=20 in this scenario. The first real telemetry tick after
    // build() still catches a drone that was already low, just one tick
    // later instead of retroactively at construction time.
    return [];
  }
}

final droneAlertProvider =
    NotifierProvider<DroneAlertNotifier, List<LogEntry>>(DroneAlertNotifier.new);
