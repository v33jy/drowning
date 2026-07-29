class Config {
  static const String serverHost =
      String.fromEnvironment('SERVER_HOST', defaultValue: 'localhost');
  static const int httpPort =
      int.fromEnvironment('HTTP_PORT', defaultValue: 8000);

  /// Offline showcase build — no server/network calls at all. [WsClient]
  /// replays a canned scenario instead of opening a real socket, and
  /// [BootScreen] skips the HTTP grid fetch. Used for static hosting
  /// (e.g. GitHub Pages) where there's no backend to reach.
  static const bool demoMode = bool.fromEnvironment('DEMO_MODE', defaultValue: false);

  static String get wsUrl => _buildUrl(secureScheme: 'wss', plainScheme: 'ws', path: '/ws/control');
  static String get baseUrl => _buildUrl(secureScheme: 'https', plainScheme: 'http');

  /// 443 포트는 Cloudflare Tunnel 같은 TLS 종단을 가리키는 관례로 취급 —
  /// 그 경우 포트를 URL에 안 붙이고 보안 스킴을 쓴다.
  static String _buildUrl({
    required String secureScheme,
    required String plainScheme,
    String path = '',
  }) {
    if (httpPort == 443) return '$secureScheme://$serverHost$path';
    return '$plainScheme://$serverHost:$httpPort$path';
  }
}
