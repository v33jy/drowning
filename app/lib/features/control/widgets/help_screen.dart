import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('도움말')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: ListView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.lg,
            ),
            children: const [
              _PageIntro(),
              _HelpSection(
                title: '지도 상태',
                children: [
                  _StatusLine(
                    color: AppColors.offline,
                    label: '미확인',
                    description: '아직 드론이 확인하지 않은 위치입니다.',
                  ),
                  _StatusLine(
                    color: AppColors.primary,
                    label: '확인 중',
                    description: '신호를 수집하고 있는 위치입니다.',
                  ),
                  _StatusLine(
                    color: AppColors.warning,
                    label: '재확인 필요',
                    description: '신호가 반복되어 다시 확인해야 하는 위치입니다.',
                  ),
                  _HelpItem(
                    title: '위치 확인',
                    description: '지도에서 셀을 누르면 우측 패널에 가까운 랜드마크와 다음 행동이 표시됩니다.',
                  ),
                ],
              ),
              _HelpSection(
                title: '탐지 대응',
                children: [
                  _HelpItem(
                    title: '1. 위치 확인',
                    description: '패널 상단의 상태와 랜드마크를 확인합니다.',
                  ),
                  _HelpItem(
                    title: '2. 현장 영상 확인',
                    description: '드론 영상을 확인한 뒤 표시된 행동에 따라 해당 위치를 재확인합니다.',
                  ),
                  _HelpItem(
                    title: '3. 결과 처리',
                    description:
                        '구조가 끝나면 구조 완료를 누릅니다. 잘못된 탐지는 깃발 버튼으로 오탐 처리합니다.',
                  ),
                ],
              ),
              _HelpSection(
                title: '음성 연결',
                children: [
                  _HelpItem(
                    title: '연결',
                    description: '영상 아래 음성 연결 버튼을 눌러 요구조자와 연결합니다.',
                  ),
                  _HelpItem(
                    title: '말하기',
                    description: '연결된 뒤 원형 마이크 버튼을 누르고 있는 동안 말합니다.',
                  ),
                  _HelpItem(
                    title: '연결이 끊긴 경우',
                    description: '일시적인 끊김은 자동으로 재연결됩니다. 재연결에 실패하면 다시 연결을 누릅니다.',
                  ),
                ],
              ),
              _HelpSection(
                title: '기록',
                children: [
                  _HelpItem(
                    title: '상황 기록 확인',
                    description:
                        '상단의 기록 메뉴에서 탐지, 구조 완료, 오탐, 음성 연결 이력을 확인할 수 있습니다.',
                  ),
                  _HelpItem(
                    title: '지도에서 다시 보기',
                    description: '기록의 위치를 선택하면 관제 지도가 해당 위치로 이동합니다.',
                  ),
                ],
              ),
              _HelpSection(
                title: '연결 문제',
                showDivider: false,
                children: [
                  _HelpItem(
                    title: '관제 연결 끊김',
                    description: '상단 연결 상태를 확인합니다. 시스템은 자동으로 다시 연결을 시도합니다.',
                  ),
                  _HelpItem(
                    title: '드론 정보가 갱신되지 않음',
                    description: '드론 배터리와 고도가 갱신되지 않으면 현장 통신 상태를 확인합니다.',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PageIntro extends StatelessWidget {
  const _PageIntro();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xl),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('관제 화면 사용 안내', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: AppSpacing.sm),
        const Text(
          '현장에서 자주 사용하는 기능만 정리했습니다.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      ],
    ),
  );
}

class _HelpSection extends StatelessWidget {
  const _HelpSection({
    required this.title,
    required this.children,
    this.showDivider = true,
  });

  final String title;
  final List<Widget> children;
  final bool showDivider;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: AppColors.navy,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      ...children,
      if (showDivider) const Divider(height: AppSpacing.xl * 2),
    ],
  );
}

class _HelpItem extends StatelessWidget {
  const _HelpItem({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 150,
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: Text(
            description,
            style: const TextStyle(color: AppColors.textSecondary, height: 1.5),
          ),
        ),
      ],
    ),
  );
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.color,
    required this.label,
    required this.description,
  });

  final Color color;
  final String label;
  final String description;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 150,
          child: Row(
            children: [
              Container(width: 8, height: 8, color: color),
              const SizedBox(width: AppSpacing.sm),
              Text(
                label,
                style: TextStyle(color: color, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        Expanded(
          child: Text(
            description,
            style: const TextStyle(color: AppColors.textSecondary, height: 1.5),
          ),
        ),
      ],
    ),
  );
}
