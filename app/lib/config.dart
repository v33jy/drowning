class Config {
  static const String serverUrl = String.fromEnvironment(
    'SERVER_URL',
    defaultValue: 'http://localhost:8000',
  );

  static const int voipPort = 5005;

  static String get baseUrl {
    if (serverUrl.endsWith('/')) {
      return serverUrl.substring(0, serverUrl.length - 1);
    }

    return serverUrl;
  }

  static String get wsUrl {
    if (baseUrl.startsWith('https://')) {
      return 'wss://${baseUrl.substring(8)}/ws/control';
    }

    if (baseUrl.startsWith('http://')) {
      return 'ws://${baseUrl.substring(7)}/ws/control';
    }

    throw StateError(
      'SERVER_URL must start with http:// or https://',
    );
  }

  // 기존 코드와의 호환성을 위한 값
  static String get serverHost => Uri.parse(baseUrl).host;
  static int get httpPort => Uri.parse(baseUrl).port;
}