import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../models/detection_event.dart';
import '../models/drone_state.dart';
import '../models/grid_cell.dart';
import '../models/heatmap_cell.dart';
import '../models/video_frame.dart';

enum ConnectionStatus { disconnected, connecting, connected }

class AppState extends ChangeNotifier {
  // -- Connection --
  ConnectionStatus connectionStatus = ConnectionStatus.disconnected;

  // -- Grid definition (fetched once on startup) --
  Map<String, CellBounds> gridDef = {};

  // -- Live state from WebSocket --
  Map<int, DroneState> drones = {};
  Map<String, HeatmapCell> heatmap = {};
  List<DetectionEvent> detections = [];

  // Latest camera frame per drone — no history, just the most recent one.
  Map<int, VideoFrameEvent> videoFrames = {};

  // Detection stream: UI subscribes to show popup without polling.
  final _detectionController = StreamController<DetectionEvent>.broadcast();
  Stream<DetectionEvent> get detectionStream => _detectionController.stream;

  // Drone stream: emits each new DroneState (used for auto-pan on first fix).
  final _droneController = StreamController<DroneState>.broadcast();
  Stream<DroneState> get droneStream => _droneController.stream;

  // -- Grid definition --
  void applyGridDef(List<dynamic> raw) {
    gridDef = {
      for (final item in raw)
        (item['cell_id'] as String): CellBounds.fromJson(item['bounds'] as Map<String, dynamic>),
    };
    notifyListeners();
  }

  // -- WebSocket message handlers --
  void applyInit(Map<String, dynamic> data) {
    _applyDrones(data['drones'] as List<dynamic>);
    _applyHeatmap(data['heatmap'] as List<dynamic>);
    for (final d in data['detections'] as List<dynamic>) {
      detections.add(DetectionEvent.fromJson(d as Map<String, dynamic>));
    }
    notifyListeners();
  }

  void updateDrone(Map<String, dynamic> json) {
    final drone = DroneState.fromJson(json);
    drones = {...drones, drone.droneId: drone}; // new map → Selector detects change
    _droneController.add(drone);
    notifyListeners();
  }

  void updateHeatmap(List<dynamic> raw) {
    _applyHeatmap(raw);
    notifyListeners();
  }

  void addDetection(Map<String, dynamic> json) {
    final event = DetectionEvent.fromJson(json);
    detections.add(event);
    _detectionController.add(event); // triggers popup in UI
    notifyListeners();
  }

  void updateVideoFrame(Map<String, dynamic> json) {
    final frame = VideoFrameEvent.fromJson(json);
    videoFrames = {...videoFrames, frame.droneId: frame}; // new map → Selector detects change
    notifyListeners();
  }

  // -- Connection status --
  void setStatus(ConnectionStatus status) {
    connectionStatus = status;
    notifyListeners();
  }

  // -- Map centre: average of active drone positions, or fallback --
  LatLng get mapCenter {
    if (drones.isEmpty) return const LatLng(37.05, 127.05);
    final lats = drones.values.map((d) => d.lat);
    final lngs = drones.values.map((d) => d.lng);
    return LatLng(
      lats.reduce((a, b) => a + b) / lats.length,
      lngs.reduce((a, b) => a + b) / lngs.length,
    );
  }

  // -- Private helpers --
  void _applyDrones(List<dynamic> raw) {
    drones = {
      for (final d in raw)
        (d['drone_id'] as int): DroneState.fromJson(d as Map<String, dynamic>),
    };
  }

  void _applyHeatmap(List<dynamic> raw) {
    heatmap = {
      for (final c in raw)
        (c['cell_id'] as String): HeatmapCell.fromJson(c as Map<String, dynamic>),
    };
  }

  @override
  void dispose() {
    _detectionController.close();
    _droneController.close();
    super.dispose();
  }
}
