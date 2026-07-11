class Config {
  static const String serverHost =
      String.fromEnvironment('SERVER_HOST', defaultValue: 'localhost');
  static const int httpPort =
      int.fromEnvironment('HTTP_PORT', defaultValue: 8000);
  static const int voipPort = 5005;

  static String get wsUrl => 'ws://$serverHost:$httpPort/ws/control';
  static String get baseUrl => 'http://$serverHost:$httpPort';
}
