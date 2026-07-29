import 'dart:convert';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Rough live-glance preview from the drone's video WebSocket stream — last
/// received frame only, no buffering or real player. Shared by the drone
/// detail bar and the detection sheet so both show the same feed the same
/// way instead of one being a real preview and the other a static
/// placeholder.
class VideoThumbnail extends StatelessWidget {
  const VideoThumbnail({super.key, required this.frameB64, this.height = 160});

  final String? frameB64;
  final double height;

  @override
  Widget build(BuildContext context) {
    // The box itself is shaped to the camera's true 16:9 ratio, not just
    // the image inside it — a width:infinity/fixed-height box left a lot of
    // bare surfaceSunken background around a small floating 16:9 image on
    // any width narrower than ~2.5x the height. Height stays the caller's
    // fixed budget (unchanged) so this can't blow the detection sheet's
    // maxHeightFraction the way a width-driven AspectRatio previously did.
    return SizedBox(
      height: height,
      child: Center(
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: Container(
              color: AppColors.surfaceSunken,
              child: frameB64 == null
                  ? const Center(
                      child: Icon(Icons.videocam_off_outlined, size: 28, color: AppColors.textSecondary),
                    )
                  : Image.memory(base64Decode(frameB64!), fit: BoxFit.contain, gaplessPlayback: true),
            ),
          ),
        ),
      ),
    );
  }
}
