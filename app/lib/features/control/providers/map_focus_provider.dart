import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../models/detection_event.dart';

/// Set by 기록 화면's "지도에서 보기" button; [ControlScreen] listens and
/// pans the map to it, then clears it back to null.
final mapFocusRequestProvider = StateProvider<LatLng?>((ref) => null);

/// 기록의 지도 아이콘이 가리키는 탐지를 관제 화면에서 함께 열기 위한 요청.
final detectionFocusRequestProvider = StateProvider<DetectionEvent?>(
  (ref) => null,
);
