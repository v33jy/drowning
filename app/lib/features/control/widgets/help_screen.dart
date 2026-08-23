import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';

class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  static const _tabs = [
    _HelpTab(Icons.radar_rounded, '탐지 대응'),
    _HelpTab(Icons.history_rounded, '기록'),
    _HelpTab(Icons.build_circle_outlined, '문제 해결'),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F6FA),
      appBar: AppBar(
        title: const Text('도움말'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: Colors.white.withValues(alpha: .16),
          ),
        ),
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: _Background()),
          LayoutBuilder(
            builder: (context, constraints) {
              final horizontal = constraints.maxWidth >= 1200
                  ? 48.0
                  : constraints.maxWidth >= 700
                  ? 28.0
                  : 16.0;
              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(horizontal, 28, horizontal, 48),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1120),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _MissionSummary(),
                        const SizedBox(height: AppSpacing.lg),
                        _GlassPanel(
                          padding: EdgeInsets.zero,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _HelpTabBar(
                                controller: _tabController,
                                tabs: _tabs,
                              ),
                              Container(
                                height: 1,
                                color: AppColors.border.withValues(alpha: .7),
                              ),
                              AnimatedBuilder(
                                animation: _tabController,
                                builder: (context, _) => AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 180),
                                  child: KeyedSubtree(
                                    key: ValueKey(_tabController.index),
                                    child: _tabContent(_tabController.index),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _tabContent(int index) => switch (index) {
    0 => const _TopicContent(
      title: '신호 발견 시 대응',
      description: '탐지 알림이 오면 아래 순서를 유지해 위치 누락과 오판을 줄이세요.',
      callout: _ActionCallout(
        title: '즉시 행동',
        description: '위험도가 높거나 요구조자가 확인되면 영상 확인 후 바로 구조 대응을 시작합니다.',
      ),
      sections: [
        _GuideSection(
          icon: Icons.location_on_rounded,
          title: '판단 순서',
          numbered: true,
          items: [
            _GuideItem('위치 확인', '격자 위치와 가까운 랜드마크를 먼저 확인합니다.'),
            _GuideItem('상태 판단', '신호 강도와 반복 여부, 현장 영상을 함께 확인합니다.'),
            _GuideItem('결과 처리', '대기로 두기·오탐 처리·구조 완료 중 현재 상황에 맞는 결과를 선택합니다.'),
          ],
        ),
        _GuideSection(
          icon: Icons.mic_rounded,
          title: '요구조자와 통화',
          items: [
            _GuideItem('음성 연결', '영상 아래 음성 연결 버튼을 누릅니다.'),
            _GuideItem('누르고 말하기', '원형 마이크 버튼을 누른 동안만 음성이 전달됩니다.'),
            _GuideItem('연결 종료', '통화가 끝나면 종료 상태를 확인한 뒤 탐지 결과를 기록합니다.'),
          ],
        ),
      ],
    ),
    1 => const _TopicContent(
      title: '상황 기록 확인',
      description: '탐지부터 구조 완료까지의 판단 근거와 처리 결과를 시간순으로 확인합니다.',
      sections: [
        _GuideSection(
          icon: Icons.manage_search_rounded,
          title: '기록 찾기',
          items: [
            _GuideItem('상단 기록 메뉴', '탐지·구조·오탐·통화 이력을 한곳에서 확인합니다.'),
            _GuideItem('시간과 상태', '발생 시각과 최종 처리 상태를 함께 비교합니다.'),
          ],
        ),
        _GuideSection(
          icon: Icons.near_me_rounded,
          title: '기록에서 다시 확인',
          items: [
            _GuideItem('위치로 이동', '기록의 위치를 선택하면 관제 지도가 해당 구역으로 이동합니다.'),
            _GuideItem('영상 재확인', '필요한 시점의 영상을 열어 현장 상황과 처리 결과를 검토합니다.'),
          ],
        ),
      ],
    ),
    _ => const _TopicContent(
      title: '연결 및 작동 문제 해결',
      description: '명령을 반복하기 전에 어느 연결이 끊겼는지 먼저 구분하세요.',
      callout: _ActionCallout(
        title: '안전 원칙',
        description: '드론 정보가 갱신되지 않으면 현재 위치를 확정할 때까지 새 이동 명령을 보내지 마세요.',
      ),
      sections: [
        _GuideSection(
          icon: Icons.wifi_off_rounded,
          title: '관제 연결이 끊긴 경우',
          items: [
            _GuideItem('상단 상태 확인', '연결 상태 표시를 확인합니다. 시스템은 자동 재연결을 시도합니다.'),
            _GuideItem('갱신 확인', '지도와 드론 상태의 최신 갱신 시각을 확인합니다.'),
            _GuideItem(
              '계속 끊기는 경우',
              '현장 통신 장비와 관제 서버 상태를 담당자에게 확인합니다.',
              warning: true,
            ),
          ],
        ),
        _GuideSection(
          icon: Icons.record_voice_over_rounded,
          title: '음성 연결이 안 되는 경우',
          items: [
            _GuideItem('재연결', '자동 재연결 실패 시 음성 연결 버튼을 다시 누릅니다.'),
            _GuideItem('마이크', '브라우저의 마이크 권한과 입력 장치를 확인합니다.'),
          ],
        ),
      ],
    ),
  };
}

class _HelpTab {
  const _HelpTab(this.icon, this.label);
  final IconData icon;
  final String label;
}

class _Background extends StatelessWidget {
  const _Background();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppColors.navy.withValues(alpha: .10),
          const Color(0xFFF2F6FA),
          const Color(0xFFF8FAFC),
        ],
        stops: const [0, .32, 1],
      ),
    ),
  );
}

class _MissionSummary extends StatelessWidget {
  const _MissionSummary();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(28),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [AppColors.navy, Color(0xFF0A3B70)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      border: Border.all(color: Colors.white.withValues(alpha: .18)),
      boxShadow: [
        BoxShadow(
          color: AppColors.navy.withValues(alpha: .18),
          blurRadius: 28,
          offset: const Offset(0, 12),
        ),
      ],
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        final intro = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '긴급 상황 판단 기준',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '알림을 받으면 이 순서대로 확인하세요.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: .76),
                fontSize: 14,
              ),
            ),
          ],
        );
        const steps = _PriorityStrip();
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [intro, const SizedBox(height: 22), steps],
          );
        }
        return Row(
          children: [
            Expanded(flex: 4, child: intro),
            const SizedBox(width: 32),
            const Expanded(flex: 6, child: _PriorityStrip()),
          ],
        );
      },
    ),
  );
}

class _PriorityStrip extends StatelessWidget {
  const _PriorityStrip();

  @override
  Widget build(BuildContext context) => Row(
    children: const [
      Expanded(child: _PriorityStep('01', '위치', Icons.location_on_rounded)),
      _StepArrow(),
      Expanded(child: _PriorityStep('02', '상태', Icons.warning_amber_rounded)),
      _StepArrow(),
      Expanded(child: _PriorityStep('03', '즉시 행동', Icons.bolt_rounded)),
    ],
  );
}

class _StepArrow extends StatelessWidget {
  const _StepArrow();

  @override
  Widget build(BuildContext context) => Icon(
    Icons.chevron_right_rounded,
    size: 20,
    color: Colors.white.withValues(alpha: .42),
  );
}

class _PriorityStep extends StatelessWidget {
  const _PriorityStep(this.number, this.label, this.icon);
  final String number;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(AppRadius.sm),
      border: Border.all(color: Colors.white.withValues(alpha: .16)),
    ),
    child: Column(
      children: [
        Icon(icon, color: Colors.white, size: 20),
        const SizedBox(height: 7),
        Text(
          '$number  $label',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class _HelpTabBar extends StatelessWidget {
  const _HelpTabBar({required this.controller, required this.tabs});
  final TabController controller;
  final List<_HelpTab> tabs;

  @override
  Widget build(BuildContext context) => Container(
    color: Colors.white.withValues(alpha: .56),
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
    child: TabBar(
      controller: controller,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      labelColor: Colors.white,
      unselectedLabelColor: AppColors.textSecondary,
      labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
      unselectedLabelStyle: const TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 14,
      ),
      dividerColor: Colors.transparent,
      indicatorSize: TabBarIndicatorSize.tab,
      indicator: BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: Colors.white.withValues(alpha: .28)),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(alpha: .16),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.only(bottom: 12),
      labelPadding: const EdgeInsets.symmetric(horizontal: 18),
      tabs: [
        for (final tab in tabs)
          Tab(
            height: 44,
            icon: Icon(tab.icon, size: 19),
            iconMargin: const EdgeInsets.only(right: 8),
            child: Text(tab.label),
          ),
      ],
    ),
  );
}

class _TopicContent extends StatelessWidget {
  const _TopicContent({
    required this.title,
    required this.description,
    required this.sections,
    this.callout,
  });
  final String title;
  final String description;
  final List<_GuideSection> sections;
  final _ActionCallout? callout;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.navy,
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          description,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14.5,
            height: 1.55,
          ),
        ),
        if (callout != null) ...[
          const SizedBox(height: AppSpacing.lg),
          callout!,
        ],
        const SizedBox(height: 26),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 760;
            if (!wide) {
              return Column(
                children: [
                  for (var i = 0; i < sections.length; i++) ...[
                    sections[i],
                    if (i < sections.length - 1)
                      const SizedBox(height: AppSpacing.md),
                  ],
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < sections.length; i++) ...[
                  Expanded(child: sections[i]),
                  if (i < sections.length - 1)
                    const SizedBox(width: AppSpacing.md),
                ],
              ],
            );
          },
        ),
      ],
    ),
  );
}

class _ActionCallout extends StatelessWidget {
  const _ActionCallout({required this.title, required this.description});
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
    decoration: BoxDecoration(
      color: AppColors.warning.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(AppRadius.sm),
      border: Border.all(color: AppColors.warning.withValues(alpha: .28)),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.priority_high_rounded,
          color: AppColors.warning,
          size: 22,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text.rich(
            TextSpan(
              style: const TextStyle(fontSize: 13.5, height: 1.45),
              children: [
                TextSpan(
                  text: '$title  ',
                  style: const TextStyle(
                    color: AppColors.warning,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                TextSpan(
                  text: description,
                  style: const TextStyle(color: AppColors.textPrimary),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _GuideSection extends StatelessWidget {
  const _GuideSection({
    required this.icon,
    required this.title,
    required this.items,
    this.numbered = false,
  });
  final IconData icon;
  final String title;
  final List<_GuideItem> items;
  final bool numbered;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: const Color(0xFFF8FAFC).withValues(alpha: .86),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      border: Border.all(color: AppColors.border.withValues(alpha: .78)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.navy.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(icon, color: AppColors.navy, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: AppColors.navy,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        for (var i = 0; i < items.length; i++) ...[
          _GuideItemRow(item: items[i], number: numbered ? i + 1 : null),
          if (i < items.length - 1)
            Padding(
              padding: const EdgeInsets.only(left: 36),
              child: Divider(
                height: 22,
                color: AppColors.border.withValues(alpha: .58),
              ),
            ),
        ],
      ],
    ),
  );
}

class _GuideItem {
  const _GuideItem(this.title, this.description, {this.warning = false});
  final String title;
  final String description;
  final bool warning;
}

class _GuideItemRow extends StatelessWidget {
  const _GuideItemRow({required this.item, this.number});
  final _GuideItem item;
  final int? number;

  @override
  Widget build(BuildContext context) {
    final accent = item.warning ? AppColors.warning : AppColors.primary;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: .10),
            shape: BoxShape.circle,
            border: Border.all(color: accent.withValues(alpha: .22)),
          ),
          child: number == null
              ? Icon(Icons.check_rounded, size: 14, color: accent)
              : Text(
                  '$number',
                  style: TextStyle(
                    color: accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                item.description,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13.5,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({required this.child, this.padding});
  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(AppRadius.lg),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .86),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: Colors.white.withValues(alpha: .96)),
          boxShadow: [
            BoxShadow(
              color: AppColors.navy.withValues(alpha: .08),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: child,
      ),
    ),
  );
}
