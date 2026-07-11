import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/detection_event.dart';
import '../models/drone_state.dart';
import '../models/grid_cell.dart';
import '../models/heatmap_cell.dart';
import '../services/voip_service.dart';
import '../state/app_state.dart';
import 'widgets/detection_dialog.dart';
import 'widgets/drone_panel.dart';
import 'widgets/heatmap_layer.dart';

class ControlScreen extends StatefulWidget {
  const ControlScreen({super.key});

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  final _mapController = MapController();
  final _voip = VoipService();
  StreamSubscription<DetectionEvent>? _detectionSub;
  StreamSubscription<DroneState>? _firstDroneSub;
  bool _panelVisible = true;
  bool _centeredOnDrone = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = context.read<AppState>();
      _detectionSub = state.detectionStream.listen(_onDetection);

      // Auto-pan to first drone telemetry received.
      _firstDroneSub = state.droneStream.listen((drone) {
        if (!_centeredOnDrone) {
          _centeredOnDrone = true;
          _mapController.move(drone.position, 15);
        }
      });
    });
  }

  @override
  void dispose() {
    _detectionSub?.cancel();
    _firstDroneSub?.cancel();
    _voip.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _onDetection(DetectionEvent event) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DetectionDialog(event: event, voip: _voip),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Row(
        children: [
          if (_panelVisible)
            Selector<AppState, Map<int, DroneState>>(
              selector: (_, s) => s.drones,
              builder: (_, drones, _) => DronePanel(drones: drones),
            ),
          Expanded(child: _buildMap()),
        ],
      ),
    );
  }

  // FlutterMap lives here permanently — never inside a Selector —
  // so the map state (position, zoom) survives data rebuilds.
  Widget _buildMap() {
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: const MapOptions(
            initialCenter: LatLng(37.5012, 127.0262), // 강남↔신논현 중간
            initialZoom: 15,
            interactionOptions: InteractionOptions(
              flags: InteractiveFlag.all,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.drone.control_app',
            ),
            // Heatmap — only the layer rebuilds, not FlutterMap.
            Selector<AppState, _HeatmapData>(
              selector: (_, s) => _HeatmapData(s.heatmap, s.gridDef),
              builder: (_, data, _) => data.gridDef.isNotEmpty
                  ? HeatmapLayer(cells: data.heatmap, gridDef: data.gridDef)
                  : const SizedBox.shrink(),
            ),
            // Drone markers — Consumer rebuilds only when notifyListeners fires.
            Consumer<AppState>(
              builder: (_, state, _) => MarkerLayer(
                markers: state.drones.values
                    .map((d) => droneMarker(d.droneId, d.position, d.battery))
                    .toList(),
              ),
            ),
          ],
        ),
        Selector<AppState, ConnectionStatus>(
          selector: (_, s) => s.connectionStatus,
          builder: (_, status, _) => _StatusBar(status: status),
        ),
        _PanelToggle(
          panelVisible: _panelVisible,
          onToggle: () => setState(() => _panelVisible = !_panelVisible),
        ),
      ],
    );
  }
}

// Data container for heatmap Selector.
class _HeatmapData {
  final Map<String, HeatmapCell> heatmap;
  final Map<String, CellBounds> gridDef;
  const _HeatmapData(this.heatmap, this.gridDef);
}

// -- Widgets --

class _StatusBar extends StatelessWidget {
  final ConnectionStatus status;
  const _StatusBar({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      ConnectionStatus.connected => ('CONNECTED', Colors.greenAccent),
      ConnectionStatus.connecting => ('CONNECTING...', Colors.orange),
      ConnectionStatus.disconnected => ('DISCONNECTED', Colors.redAccent),
    };
    return Positioned(
      top: 12,
      left: 12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PanelToggle extends StatelessWidget {
  final bool panelVisible;
  final VoidCallback onToggle;
  const _PanelToggle({required this.panelVisible, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 12,
      right: 12,
      child: FloatingActionButton.small(
        onPressed: onToggle,
        backgroundColor: Colors.black.withValues(alpha: 0.75),
        child: Icon(
          panelVisible ? Icons.chevron_left : Icons.chevron_right,
          color: Colors.white,
        ),
      ),
    );
  }
}
