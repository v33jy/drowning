import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/severity.dart';
import '../../core/widgets/status_chip.dart';
import '../control/providers/grid_provider.dart';
import '../control/providers/ws_providers.dart';
import 'providers/settings_provider.dart';

/// 설정 — 서버 주소/포트(그룹 1), 권한 상태(그룹 2), 버전(그룹 3). 표준
/// 그룹핑 리스트 폼, 특별한 컴포넌트 없음.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  PermissionStatus? _micStatus;

  @override
  void initState() {
    super.initState();
    _refreshMicStatus();
  }

  Future<void> _refreshMicStatus() async {
    final status = await Permission.microphone.status;
    if (mounted) setState(() => _micStatus = status);
  }

  Future<void> _editHost() async {
    final settings = ref.read(settingsProvider);
    final controller = TextEditingController(text: settings.serverHost);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Server URL'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('취소')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      await ref.read(settingsProvider.notifier).update(serverHost: result);
      await _reconnect();
    }
  }

  Future<void> _editPort() async {
    final settings = ref.read(settingsProvider);
    final controller = TextEditingController(text: settings.httpPort.toString());
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Port'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('취소')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    final port = int.tryParse(result ?? '');
    if (port != null) {
      await ref.read(settingsProvider.notifier).update(httpPort: port);
      await _reconnect();
    }
  }

  Future<void> _reconnect() async {
    final settings = ref.read(settingsProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await fetchAndApplyGrid(ref, settings.baseUrl);
      await ref.read(wsClientProvider).connect(settings.wsUrl);
      if (mounted) {
        messenger.showSnackBar(const SnackBar(content: Text('서버 설정 저장됨 · 재연결 중')));
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('재연결 실패: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        children: [
          const _GroupLabel('서버'),
          ListTile(
            title: const Text('Server URL'),
            trailing: Text(settings.serverHost, style: const TextStyle(color: AppColors.textSecondary)),
            onTap: _editHost,
          ),
          ListTile(
            title: const Text('Port'),
            trailing: Text('${settings.httpPort}', style: const TextStyle(color: AppColors.textSecondary)),
            onTap: _editPort,
          ),
          const Divider(height: AppSpacing.xl),
          const _GroupLabel('권한'),
          ListTile(
            title: const Text('마이크'),
            trailing: _micStatus == null
                ? const SizedBox.shrink()
                : StatusChip(
                    severity: _micStatus!.isGranted ? Severity.ok : Severity.danger,
                    label: _micStatus!.isGranted ? '허용됨' : '거부됨',
                  ),
            onTap: () async {
              await openAppSettings();
              _refreshMicStatus();
            },
          ),
          const Divider(height: AppSpacing.xl),
          const _GroupLabel('정보'),
          const ListTile(
            title: Text('버전'),
            trailing: Text('1.0.0', style: TextStyle(color: AppColors.textSecondary)),
          ),
        ],
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xs),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.04,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}
