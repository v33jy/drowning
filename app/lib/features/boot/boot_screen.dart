import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';

import '../../config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../models/grid_cell.dart';
import '../../navigation/root_shell.dart';
import '../control/providers/grid_provider.dart';
import '../control/providers/ws_providers.dart';

enum _BootPhase { splash, connecting, failed, success }

/// Entry flow — Splash → 권한 rationale(Dialog) → 서버 연결 → 실패 시 Retry.
/// One route, branching on [_BootPhase], per the confirmed design (this
/// replaces what used to be 4 separate conceptual screens).
class BootScreen extends ConsumerStatefulWidget {
  const BootScreen({super.key});

  @override
  ConsumerState<BootScreen> createState() => _BootScreenState();
}

class _BootScreenState extends ConsumerState<BootScreen> {
  _BootPhase _phase = _BootPhase.splash;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    await Future.delayed(const Duration(milliseconds: 800)); // splash 최소 노출
    if (!mounted) return;
    await _requestMicPermission();
    if (!mounted) return;
    setState(() => _phase = _BootPhase.connecting);
    await _connectToServer();
  }

  Future<void> _requestMicPermission() async {
    final proceed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.mic_none, color: AppColors.primary, size: 32),
            title: const Text('마이크 권한이 필요해요'),
            content: const Text('요구조자와 음성으로 통화하려면 마이크 권한이 필요합니다.'),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('확인'),
              ),
            ],
          ),
        ) ??
        false;
    if (proceed) {
      await Permission.microphone.request();
    }
    // 거부돼도 부팅은 계속 진행 — 통화 버튼 쪽에서 권한 거부 상태를 다룬다.
  }

  Future<void> _connectToServer() async {
    try {
      final res = await http.get(Uri.parse('${Config.baseUrl}/heatmap/grid'));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final grid = jsonDecode(res.body) as List<dynamic>;
      if (!mounted) return;

      ref.read(gridDefProvider.notifier).state = {
        for (final item in grid)
          (item['cell_id'] as String):
              CellBounds.fromJson(item['bounds'] as Map<String, dynamic>),
      };
      await ref.read(wsClientProvider).connect();

      if (!mounted) return;
      setState(() => _phase = _BootPhase.success);
    } catch (e) {
      if (mounted) {
        setState(() {
          _phase = _BootPhase.failed;
          _error = e.toString();
        });
      }
    }
  }

  void _retry() {
    setState(() {
      _phase = _BootPhase.connecting;
      _error = null;
    });
    _connectToServer();
  }

  @override
  Widget build(BuildContext context) {
    if (_phase == _BootPhase.success) return const RootShell();

    final Widget content = switch (_phase) {
      _BootPhase.splash => const _SplashBody(),
      _BootPhase.connecting => const _ConnectingBody(),
      _BootPhase.failed => _FailureBody(message: _error!, onRetry: _retry),
      _BootPhase.success => const SizedBox.shrink(),
    };

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(child: content),
    );
  }
}

class _SplashBody extends StatelessWidget {
  const _SplashBody();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Spacer(),
        const Icon(Icons.satellite_alt_outlined,
            size: 48, color: AppColors.primary),
        const SizedBox(height: AppSpacing.md),
        Text('Mission Control', style: Theme.of(context).textTheme.displaySmall),
        const Spacer(),
        const Padding(
          padding: EdgeInsets.only(bottom: AppSpacing.xl),
          child: Text('v1.0.0',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ),
      ],
    );
  }
}

class _ConnectingBody extends StatelessWidget {
  const _ConnectingBody();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: AppColors.primary),
          const SizedBox(height: AppSpacing.lg),
          Text('서버에 연결하는 중…', style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _FailureBody extends StatelessWidget {
  const _FailureBody({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppColors.danger, size: 48),
            const SizedBox(height: AppSpacing.lg),
            Text(
              '서버에 연결할 수 없습니다',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              message,
              style: Theme.of(context).textTheme.labelSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton(onPressed: onRetry, child: const Text('다시 시도')),
          ],
        ),
      ),
    );
  }
}
