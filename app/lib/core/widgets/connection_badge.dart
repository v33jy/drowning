import 'package:flutter/material.dart';

import 'severity.dart';
import 'status_chip.dart';

/// Server WebSocket connection state — distinct from an individual drone
/// going offline (see [Severity.offline] used per-drone elsewhere).
enum ConnectionStatus { connecting, connected, disconnected }

/// Presentational only — the screen that hosts this watches whichever
/// connection provider it wires up and passes the current [status] in.
class ConnectionBadge extends StatelessWidget {
  const ConnectionBadge({super.key, required this.status});

  final ConnectionStatus status;

  @override
  Widget build(BuildContext context) {
    final (severity, label) = switch (status) {
      ConnectionStatus.connected => (Severity.ok, '연결됨'),
      ConnectionStatus.connecting => (Severity.offline, '재연결 중…'),
      ConnectionStatus.disconnected => (Severity.danger, '연결 끊김'),
    };
    return StatusChip(severity: severity, label: label);
  }
}
