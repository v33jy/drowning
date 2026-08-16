import 'dart:async';
import 'dart:math';

import '../../../models/grid_cell.dart';
import 'ws_client.dart';

class _DemoCellSummary {
  _DemoCellSummary(this.cellId);

  final String cellId;
  final List<double> _recentRss = [];
  final Set<int> _droneIds = {};
  int sampleCount = 0;
  int? latestDroneId;
  double? latestRssDbm;
  double? lastUpdated;

  void record(int droneId, double rssDbm, double measuredAt) {
    _recentRss.add(rssDbm);
    if (_recentRss.length > DemoFeed.recentWindow) {
      _recentRss.removeAt(0);
    }
    _droneIds.add(droneId);
    sampleCount += 1;
    latestDroneId = droneId;
    latestRssDbm = rssDbm;
    lastUpdated = measuredAt;
  }

  Map<String, dynamic> toJson() {
    final sorted = [..._recentRss]..sort();
    final middle = sorted.length ~/ 2;
    final representative = sorted.length.isOdd
        ? sorted[middle]
        : (sorted[middle - 1] + sorted[middle]) / 2;
    final strongCount = _recentRss
        .where((rss) => rss >= DemoFeed.recheckRssDbm)
        .length;
    final needsRecheck = strongCount >= DemoFeed.recheckMinSamples;

    return {
      'cell_id': cellId,
      'drone_id': latestDroneId,
      'rss_dbm': representative,
      'latest_rss_dbm': latestRssDbm,
      'average_rss_dbm': _recentRss.reduce((a, b) => a + b) / _recentRss.length,
      'peak_rss_dbm': _recentRss.reduce(max),
      'sample_count': sampleCount,
      'drone_count': _droneIds.length,
      'strong_signal_count': strongCount,
      'color': needsRecheck ? '#F57C00' : '#1976D2',
      'status': needsRecheck ? 'needs_recheck' : 'scanning',
      'status_reason': needsRecheck
          ? 'repeated_strong_signal'
          : 'insufficient_repeated_signal',
      'last_updated': lastUpdated,
    };
  }
}

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
  static const recentWindow = 10;
  static const recheckRssDbm = -65.0;
  static const recheckMinSamples = 3;

  static const _startLat = 37.4979, _startLng = 127.0276;
  static const _targetLat = 37.5044, _targetLng = 127.0248;
  static const _approachSteps = 30;

  static const locationLabels = <String, String>{'F2': '신논현역 인근'};

  static String _cellId(int row, int col) =>
      '${String.fromCharCode(65 + row)}$col';

  static String? cellIdFor(double lat, double lng) {
    if (lat < _latMin || lat > _latMax || lng < _lngMin || lng > _lngMax) {
      return null;
    }
    final row = (((lat - _latMin) / (_latMax - _latMin)) * _gridRows)
        .floor()
        .clamp(0, _gridRows - 1);
    final col = (((lng - _lngMin) / (_lngMax - _lngMin)) * _gridCols)
        .floor()
        .clamp(0, _gridCols - 1);
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

  /// Every scanned cell along the drone's path so far — unscanned ones are
  /// simply omitted, matching how a fresh grid looks before the drone
  /// reaches them (the app already renders missing cells as unscanned).
  static List<Map<String, dynamic>> _heatmapSnapshot(
    List<({double lat, double lng, int droneId, double measuredAt})> track,
  ) {
    final byCell = <String, _DemoCellSummary>{};
    for (final p in track) {
      final id = cellIdFor(p.lat, p.lng);
      if (id == null) continue;
      final rss = _rssAt(p.lat, p.lng);
      byCell
          .putIfAbsent(id, () => _DemoCellSummary(id))
          .record(p.droneId, rss, p.measuredAt);
    }
    return byCell.values.map((cell) => cell.toJson()).toList();
  }

  /// Starts emitting `init` → periodic `drone_update`/`heatmap_update` →
  /// one `detection` into [client], replaying the approach-and-hover
  /// scenario. Returns the [Timer] so the caller can cancel it on dispose.
  static Timer start(WsClient client) {
    const droneId = 1;
    var step = 0;
    var battery = 100.0;
    var detectionFired = false;
    final track =
        <({double lat, double lng, int droneId, double measuredAt})>[];

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

      track.add((
        lat: lat,
        lng: lng,
        droneId: droneId,
        measuredAt: DateTime.now().millisecondsSinceEpoch / 1000,
      ));

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
            'call_session_id':
                'demo-call-${DateTime.now().millisecondsSinceEpoch}',
            'stream_url': null,
          });
        }
      }
    });
  }
}
