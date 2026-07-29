import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config.dart';

class AppSettings {
  const AppSettings({required this.serverHost, required this.httpPort});

  final String serverHost;
  final int httpPort;

  // 443 포트는 Cloudflare Tunnel 같은 TLS 종단을 가리키는 관례로 취급 —
  // 그 경우 포트를 URL에 안 붙이고 보안 스킴을 쓴다.
  String get baseUrl => httpPort == 443 ? 'https://$serverHost' : 'http://$serverHost:$httpPort';
  String get wsUrl => httpPort == 443
      ? 'wss://$serverHost/ws/control'
      : 'ws://$serverHost:$httpPort/ws/control';
}

/// 서버 주소는 빌드 시 고정되는 값([Config])이라 런타임에 바꿀 수 없다 —
/// 현장 배치된 관제 앱이 임의로 다른 백엔드에 붙는 걸 막기 위해 설정
/// 화면에 편집 UI를 두지 않는다.
final settingsProvider = Provider<AppSettings>(
  (ref) => const AppSettings(serverHost: Config.serverHost, httpPort: Config.httpPort),
);
