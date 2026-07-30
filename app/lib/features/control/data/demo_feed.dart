import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../../models/grid_cell.dart';
import 'ws_client.dart';

/// Canned replay of the same 강남역→신논현역 scenario `scenario.py` /
/// `pi/gateway`'s mock mode use — for [Config.demoMode], where there's no
/// server to talk to at all (static hosting). Feeds [WsClient]'s own
/// message stream directly, so every provider downstream (drones/heatmap/
/// detection) behaves exactly as it would against a real connection.
class DemoFeed {
  DemoFeed._();

  static const _latMin = 37.490, _latMax = 37.515;
  static const _lngMin = 127.020, _lngMax = 127.040;
  static const _gridRows = 10, _gridCols = 10;
  static const _rssMin = -100.0, _rssMax = -40.0;

  static const _startLat = 37.4979, _startLng = 127.0276;
  static const _targetLat = 37.5044, _targetLng = 127.0248;
  static const _approachSteps = 30;

  static String _cellId(int row, int col) => '${String.fromCharCode(65 + row)}$col';

  static String? cellIdFor(double lat, double lng) {
    if (lat < _latMin || lat > _latMax || lng < _lngMin || lng > _lngMax) return null;
    final row = (((lat - _latMin) / (_latMax - _latMin)) * _gridRows).floor().clamp(0, _gridRows - 1);
    final col = (((lng - _lngMin) / (_lngMax - _lngMin)) * _gridCols).floor().clamp(0, _gridCols - 1);
    return _cellId(row, col);
  }

  /// Same shape `fetchAndApplyGrid` builds from the real `/heatmap/grid`
  /// response — for seeding [gridDefProvider] with no HTTP call.
  static Map<String, CellBounds> gridDef() {
    final rowH = (_latMax - _latMin) / _gridRows;
    final colW = (_lngMax - _lngMin) / _gridCols;
    return {
      for (var row = 0; row < _gridRows; row++)
        for (var col = 0; col < _gridCols; col++)
          _cellId(row, col): CellBounds(
            latMin: _latMin + row * rowH,
            latMax: _latMin + (row + 1) * rowH,
            lngMin: _lngMin + col * colW,
            lngMax: _lngMin + (col + 1) * colW,
          ),
    };
  }

  static double _rssAt(double lat, double lng) {
    final dist = sqrt(pow(lat - _targetLat, 2) + pow(lng - _targetLng, 2));
    return (-40.0 - dist * 3000).clamp(_rssMin, _rssMax);
  }

  static String _rssToColorHex(double rssDbm) {
    final ratio = ((rssDbm - _rssMin) / (_rssMax - _rssMin)).clamp(0.0, 1.0);
    final hue = (1.0 - ratio) * 240.0;
    final color = HSVColor.fromAHSV(1.0, hue, 1.0, 1.0).toColor();
    String hex(int v) => v.toRadixString(16).padLeft(2, '0').toUpperCase();
    return '#${hex((color.r * 255).round())}${hex((color.g * 255).round())}${hex((color.b * 255).round())}';
  }

  /// Every scanned cell along the drone's path so far — unscanned ones are
  /// simply omitted, matching how a fresh grid looks before the drone
  /// reaches them (the app already renders missing cells as unscanned).
  static List<Map<String, dynamic>> _heatmapSnapshot(List<({double lat, double lng, int droneId})> track) {
    final byCell = <String, Map<String, dynamic>>{};
    for (final p in track) {
      final id = cellIdFor(p.lat, p.lng);
      if (id == null) continue;
      final rss = _rssAt(p.lat, p.lng);
      byCell[id] = {
        'cell_id': id,
        'drone_id': p.droneId,
        'rss_dbm': rss,
        'color': _rssToColorHex(rss),
        'status': 'active',
      };
    }
    return byCell.values.toList();
  }

  /// Starts emitting `init` → periodic `drone_update`/`heatmap_update` →
  /// one `detection` into [client], replaying the approach-and-hover
  /// scenario. Returns the [Timer] so the caller can cancel it on dispose.
  static Timer start(WsClient client) {
    const droneId = 1;
    var step = 0;
    var battery = 100.0;
    var detectionFired = false;
    final track = <({double lat, double lng, int droneId})>[];

    void emitInit() {
      client.emitDemo('init', {
        'drones': [
          {
            'drone_id': droneId,
            'lat': _startLat,
            'lng': _startLng,
            'altitude': 50.0,
            'battery': battery.round(),
            'status': 'active',
          },
        ],
        'heatmap': _heatmapSnapshot(track),
      });
    }

    emitInit();

    return Timer.periodic(const Duration(seconds: 2), (timer) {
      step = min(step + 1, _approachSteps + 6); // a few extra ticks hovering
      final t = min(step, _approachSteps) / _approachSteps;
      final lat = _startLat + (_targetLat - _startLat) * t;
      final lng = _startLng + (_targetLng - _startLng) * t;
      battery = max(20.0, battery - 0.6);

      track.add((lat: lat, lng: lng, droneId: droneId));

      client.emitDemo('drone_update', {
        'drone_id': droneId,
        'lat': lat,
        'lng': lng,
        'altitude': 50.0,
        'battery': battery.round(),
        'status': 'active',
        'cell_id': cellIdFor(lat, lng),
      });
      client.emitDemo('heatmap_update', _heatmapSnapshot(track));

      if (!detectionFired && step >= _approachSteps) {
        detectionFired = true;
        final cellId = cellIdFor(_targetLat, _targetLng);
        if (cellId != null) {
          client.emitDemo('detection', {
            'drone_id': droneId,
            'cell_id': cellId,
            'rss_dbm': _rssAt(_targetLat, _targetLng),
            'timestamp': DateTime.now().millisecondsSinceEpoch / 1000,
            'detection_id': 'demo-${DateTime.now().millisecondsSinceEpoch}',
            'stream_url': null,
          });
        }
      }
    });
  }
}
