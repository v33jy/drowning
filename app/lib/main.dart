import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import 'config.dart';
import 'screens/control_screen.dart';
import 'services/ws_service.dart';
import 'state/app_state.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Lock to landscape for tablet use.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await Permission.microphone.request();
  runApp(const DroneControlApp());
}

class DroneControlApp extends StatelessWidget {
  const DroneControlApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(),
      child: MaterialApp(
        title: 'Drone Control',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: Colors.orangeAccent),
        ),
        home: const _Bootstrapper(),
      ),
    );
  }
}

// Fetches the grid definition once on startup, then opens the WebSocket.
class _Bootstrapper extends StatefulWidget {
  const _Bootstrapper();

  @override
  State<_Bootstrapper> createState() => _BootstrapperState();
}

class _BootstrapperState extends State<_Bootstrapper> {
  WsService? _ws;
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final res =
          await http.get(Uri.parse('${Config.baseUrl}/heatmap/grid'));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');

      final grid = jsonDecode(res.body) as List<dynamic>;
      if (!mounted) return;
      context.read<AppState>().applyGridDef(grid);

      _ws = WsService(context.read<AppState>());
      await _ws!.connect();
      setState(() => _ready = true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    _ws?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, color: Colors.redAccent, size: 48),
              const SizedBox(height: 16),
              Text('Cannot reach server\n${Config.baseUrl}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => setState(() {
                  _error = null;
                  _init();
                }),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (!_ready) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.orangeAccent),
              SizedBox(height: 16),
              Text('Connecting to server...',
                  style: TextStyle(color: Colors.white54)),
            ],
          ),
        ),
      );
    }

    return const ControlScreen();
  }
}
