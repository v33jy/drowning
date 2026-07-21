import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/grid_cell.dart';

/// Grid definition — fetched once over HTTP during boot, then read-only.
final gridDefProvider = StateProvider<Map<String, CellBounds>>((ref) => {});
