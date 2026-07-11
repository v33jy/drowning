"""
Video streaming endpoint
=========================
The drone-side PC (OpenCV + ArduCam) posts camera frames here; each frame is
relayed to connected app clients over the WebSocket channel.
"""

from __future__ import annotations

from fastapi import APIRouter, Path

import services
from models import VideoFrame

router = APIRouter(prefix="/drones", tags=["video"])


@router.post("/{drone_id}/video", summary="Submit a video frame for the drone's camera feed")
async def submit_video_frame(
    frame: VideoFrame,
    drone_id: int = Path(..., ge=1),
) -> dict:
    await services.submit_video_frame(drone_id, frame)
    return {"ok": True}
