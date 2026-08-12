import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/severity.dart';
import '../../../core/widgets/status_chip.dart';

/// 도움말 — 화면 구성·상태 색상·아이콘·문제 해결을 한 화면에 모은 참고
/// 문서. "범례"(색상표 하나)보다 넓게 잡은 이유: 마커 색만 설명해서는
/// 이 화면 자체가 왜 존재하는지, 다른 화면들이 뭘 하는지 안 알려줘서
/// 내용이 지나치게 빈약했다 — 메뉴에서 기록/설정과 같은 층위에 있는
/// 화면이라면 그만한 무게가 있어야 한다.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('도움말')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: const [
          _HelpSection(
            title: '화면 구성',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _HelpRow(
                  icon: Icons.podcasts,
                  label: '연결 상태 · 드론 수',
                  description: '지도 좌측 상단 배지. 서버 연결이 끊기면 자동으로 재연결을 시도합니다.',
                ),
                _HelpRow(
                  icon: Icons.priority_high,
                  label: '미확인 탐지',
                  description: '처리하지 않은 탐지 건수. 탭하면 대기 중인 첫 번째 탐지를 다시 엽니다.',
                ),
                _HelpRow(
                  icon: Icons.menu_outlined,
                  label: '메뉴',
                  description: '기록 · 도움말 · 설정으로 이동합니다.',
                ),
                _HelpRow(
                  icon: Icons.list_alt_outlined,
                  label: '드론 목록 바',
                  description:
                      '화면 하단 고정. 드론을 탭하면 배터리 · 위치 · 실시간 영상 프리뷰가 펼쳐집니다.',
                ),
              ],
            ),
          ),
          SizedBox(height: AppSpacing.lg),
          _HelpSection(
            title: '드론 상태',
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                StatusChip(severity: Severity.ok, label: '정상'),
                StatusChip(severity: Severity.warning, label: '주의(배터리 40% 이하)'),
                StatusChip(severity: Severity.danger, label: '위험(배터리 20% 이하)'),
                StatusChip(severity: Severity.offline, label: 'Offline(신호 상실)'),
              ],
            ),
          ),
          SizedBox(height: AppSpacing.lg),
          _HelpSection(
            title: '구조 탐색 지도',
            child: Text(
              '회색은 아직 확인되지 않은 구역, 파란색은 확인 중인 구역, '
              '주황색은 구조 신호가 반복되어 추가 확인이 필요한 구역입니다. '
              '지도에서 구역을 누르면 판정 이유와 권장 조치를 확인할 수 있습니다. '
              '지도 표시는 구조 대상자의 위치를 확정하지 않습니다.',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
          ),
          SizedBox(height: AppSpacing.lg),
          _HelpSection(
            title: '탐지 알림 처리',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _HelpRow(
                  icon: Icons.check_circle_outline,
                  label: '구조 완료',
                  description: '처리 완료로 기록하고 기록 화면에 남깁니다.',
                ),
                _HelpRow(
                  icon: Icons.flag_outlined,
                  label: '오탐 처리',
                  description: '확인 다이얼로그를 거친 뒤 목록에서 제거합니다 — 되돌릴 수 없습니다.',
                ),
                _HelpRow(
                  icon: Icons.remove_circle_outline,
                  label: '최소화',
                  description: '처리하지 않고 닫습니다. 미확인 탐지 배지에 남아 있다가 다시 열 수 있습니다.',
                ),
              ],
            ),
          ),
          SizedBox(height: AppSpacing.lg),
          _HelpSection(
            title: '기록 화면',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _HelpRow(
                  icon: Icons.filter_alt_outlined,
                  label: '전체 · 미확인',
                  description: '미확인은 아직 처리하지 않은 탐지만 모아서 보여줍니다.',
                ),
                _HelpRow(
                  icon: Icons.search,
                  label: '검색 · 필터',
                  description: '드론 · 셀 검색, 날짜 · 드론 · 상태별로 좁혀볼 수 있습니다.',
                ),
              ],
            ),
          ),
          SizedBox(height: AppSpacing.lg),
          _HelpSection(
            title: '문제 해결',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _HelpRow(
                  icon: Icons.wifi_off,
                  label: '서버 연결 끊김',
                  description: '연결 상태 배지가 "연결 끊김"으로 바뀌며, 앱이 자동으로 재연결을 시도합니다.',
                ),
                _HelpRow(
                  icon: Icons.signal_wifi_off,
                  label: '드론 신호 상실',
                  description: '해당 드론만 텔레메트리가 끊긴 경우로, 지도 상단에 별도 배너로 안내됩니다.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Bordered "reference document" card — every 도움말 항목이 자유 형식
/// 텍스트 나열이 아니라 규정집 조항처럼 구획된 느낌을 준다.
class _HelpSection extends StatelessWidget {
  const _HelpSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTypography.eyebrow(AppColors.navy)),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}

/// icon + 항목명 + 설명 — 실제 화면에 쓰이는 아이콘을 그대로 가져와서
/// "이 아이콘을 보면 이런 뜻" 매핑까지 한 번에 겸한다.
class _HelpRow extends StatelessWidget {
  const _HelpRow({
    required this.icon,
    required this.label,
    required this.description,
  });

  final IconData icon;
  final String label;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.navy),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
