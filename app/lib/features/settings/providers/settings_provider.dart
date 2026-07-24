import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config.dart';

class AppSettings {
  const AppSettings({required this.serverHost, required this.httpPort});

  final String serverHost;
  final int httpPort;

  String get baseUrl => 'http://$serverHost:$httpPort';
  String get wsUrl => 'ws://$serverHost:$httpPort/ws/control';

  AppSettings copyWith({String? serverHost, int? httpPort}) => AppSettings(
        serverHost: serverHost ?? this.serverHost,
        httpPort: httpPort ?? this.httpPort,
      );
}

/// [Config]'s compile-time values are only the fallback default — 설정
/// 화면에서 바꾼 값은 SharedPreferences에 저장되고 다음 실행에도 유지된다.
class SettingsNotifier extends Notifier<AppSettings> {
  static const _keyHost = 'server_host';
  static const _keyPort = 'http_port';
  Future<void>? _loadFuture;

  @override
  AppSettings build() {
    _loadFuture = _load();
    return const AppSettings(serverHost: Config.serverHost, httpPort: Config.httpPort);
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final host = prefs.getString(_keyHost);
    final port = prefs.getInt(_keyPort);
    if (host != null || port != null) {
      state = state.copyWith(serverHost: host, httpPort: port);
    }
  }

  /// [BootScreen] awaits this before its first connect, so a previously
  /// saved server address is honored instead of racing the default.
  Future<void> ensureLoaded() => _loadFuture ?? Future.value();

  Future<void> update({String? serverHost, int? httpPort}) async {
    state = state.copyWith(serverHost: serverHost, httpPort: httpPort);
    final prefs = await SharedPreferences.getInstance();
    if (serverHost != null) await prefs.setString(_keyHost, serverHost);
    if (httpPort != null) await prefs.setInt(_keyPort, httpPort);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
