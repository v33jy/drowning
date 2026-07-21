import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/control/control_screen.dart';
import '../features/log/log_screen.dart';
import '../features/settings/settings_screen.dart';
import 'tab_index_provider.dart';

/// Post-boot entry point — flat 3-tab structure (관제/기록/설정), per the
/// confirmed navigation design. "드론 관리" has no tab of its own (folded
/// into the 관제 tab's drone list sheet); 탐지 이력/알림 센터 are one merged
/// "기록" tab, not two.
class RootShell extends ConsumerWidget {
  const RootShell({super.key});

  static const _tabs = [
    ControlScreen(),
    LogScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(tabIndexProvider);

    return Scaffold(
      body: IndexedStack(index: index, children: _tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => ref.read(tabIndexProvider.notifier).state = i,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: '관제',
          ),
          NavigationDestination(
            icon: Icon(Icons.list_alt_outlined),
            selectedIcon: Icon(Icons.list_alt),
            label: '기록',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '설정',
          ),
        ],
      ),
    );
  }
}
