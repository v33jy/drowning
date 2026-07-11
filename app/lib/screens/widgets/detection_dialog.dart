import 'dart:async' show unawaited;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/detection_event.dart';
import '../../services/voip_service.dart';
import '../../state/app_state.dart';

class DetectionDialog extends StatefulWidget {
  final DetectionEvent event;
  final VoipService voip;

  const DetectionDialog({super.key, required this.event, required this.voip});

  @override
  State<DetectionDialog> createState() => _DetectionDialogState();
}

class _DetectionDialogState extends State<DetectionDialog> {
  bool _callActive = false;

  @override
  void dispose() {
    // stopCall() is async; unawaited is intentional — dispose() must be sync.
    // VoipService is owned by ControlScreen, so cleanup continues after dialog closes.
    if (_callActive) unawaited(widget.voip.stopCall());
    super.dispose();
  }

  Future<void> _toggleCall() async {
    if (_callActive) {
      await widget.voip.stopCall();
      if (mounted) setState(() => _callActive = false);
    } else {
      // startCall is best-effort; always flip UI so button responds visibly.
      unawaited(widget.voip.startCall(widget.event.voipSessionId));
      if (mounted) setState(() => _callActive = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1A1A2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: Colors.orangeAccent, size: 28),
                const SizedBox(width: 12),
                const Text(
                  'SURVIVOR DETECTED',
                  style: TextStyle(
                    color: Colors.orangeAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    letterSpacing: 1.2,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _VideoPreview(droneId: widget.event.droneId),
            const SizedBox(height: 16),
            _InfoRow('Drone', '#${widget.event.droneId}'),
            _InfoRow('Cell', widget.event.cellId),
            _InfoRow('Signal', '${widget.event.rssDbm.toStringAsFixed(1)} dBm'),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor:
                      _callActive ? Colors.redAccent : Colors.greenAccent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _toggleCall,
                icon: Icon(_callActive ? Icons.call_end : Icons.call),
                label: Text(
                  _callActive ? 'End Call' : 'Connect Voice Channel',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoPreview extends StatelessWidget {
  final int droneId;
  const _VideoPreview({required this.droneId});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 300,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      clipBehavior: Clip.antiAlias,
      child: Selector<AppState, Uint8List?>(
        selector: (_, s) => s.videoFrames[droneId]?.bytes,
        builder: (_, bytes, _) => bytes == null
            ? const Center(
                child: Text(
                  'NO VIDEO SIGNAL',
                  style: TextStyle(color: Colors.white38, fontSize: 12, letterSpacing: 1.2),
                ),
              )
            // gaplessPlayback avoids a flash back to empty while the next
            // frame decodes — frames arrive several times a second.
            : Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(label,
                style: const TextStyle(color: Colors.white54, fontSize: 13)),
          ),
          Text(value,
              style: const TextStyle(color: Colors.white, fontSize: 13)),
        ],
      ),
    );
  }
}
