import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

/// Set by 기록 화면's "지도에서 보기" button; [ControlScreen] listens and
/// pans the map to it, then clears it back to null.
final mapFocusRequestProvider = StateProvider<LatLng?>((ref) => null);
