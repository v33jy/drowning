import 'package:flutter/material.dart';

import '../../models/drone_state.dart';

class DronePanel extends StatelessWidget {
  final Map<int, DroneState> drones;
  const DronePanel({super.key, required this.drones});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      color: Colors.black87,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 16, 12, 8),
            child: Text(
              'DRONES',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 11,
                letterSpacing: 1.5,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Divider(color: Colors.white24, height: 1),
          Expanded(
            child: drones.isEmpty
                ? const Center(
                    child: Text('No drones connected',
                        style: TextStyle(color: Colors.white38, fontSize: 12)),
                  )
                : ListView(
                    children: drones.values
                        .map((d) => _DroneTile(drone: d))
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

class _DroneTile extends StatelessWidget {
  final DroneState drone;
  const _DroneTile({required this.drone});

  @override
  Widget build(BuildContext context) {
    final batteryColor = drone.battery > 50
        ? Colors.greenAccent
        : drone.battery > 20
            ? Colors.orange
            : Colors.redAccent;

    final statusColor = switch (drone.status) {
      'active' => Colors.greenAccent,
      'returning' => Colors.orange,
      _ => Colors.redAccent,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.flight, color: statusColor, size: 16),
              const SizedBox(width: 6),
              Text(
                'Drone #${drone.droneId}',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                drone.status.toUpperCase(),
                style: TextStyle(color: statusColor, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.battery_full, color: batteryColor, size: 14),
              const SizedBox(width: 4),
              SizedBox(
                width: 80,
                child: LinearProgressIndicator(
                  value: drone.battery / 100,
                  backgroundColor: Colors.white24,
                  color: batteryColor,
                  minHeight: 4,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${drone.battery}%',
                style: TextStyle(color: batteryColor, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '↑ ${drone.altitude.toStringAsFixed(0)} m   '
            '${drone.lat.toStringAsFixed(4)}, ${drone.lng.toStringAsFixed(4)}',
            style: const TextStyle(color: Colors.white54, fontSize: 10),
          ),
          if (drone.cellId != null)
            Text(
              'Cell: ${drone.cellId}',
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
          const Divider(color: Colors.white12, height: 16),
        ],
      ),
    );
  }
}
