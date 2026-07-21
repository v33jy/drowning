import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which bottom-nav tab is active. A plain local `int` in [RootShell] would
/// work for the tab bar itself, but 기록 화면's "지도에서 보기" button needs
/// to switch tabs from outside the shell, so it lives in a provider instead.
final tabIndexProvider = StateProvider<int>((ref) => 0);
