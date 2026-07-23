"""
Video streaming endpoint
=========================
The drone-side PC (OpenCV/picamera2 + camera module) opens one WebSocket
connection here and pushes a continuous stream of raw JPEG frames (one
binary WS message per frame). Each frame is relayed to connected app
clients over the existing /ws/control channel.

Why WebSocket instead of POST-per-frame:
  A fresh HTTP request per frame pays a TCP/HTTP round trip on every single
  frame, which is what made the old endpoint feel laggy. A single persistent
  connection removes that per-frame overhead and turns this into an actual
  stream.
"""

from __future__ import annotations

from fastapi import APIRouter, Path, WebSocket, WebSocketDisconnect

import services
import state

router = APIRouter(prefix="/drones", tags=["video"])


@router.websocket("/{drone_id}/video")
async def stream_video_frames(ws: WebSocket, drone_id: int = Path(..., ge=1)) -> None:
    if drone_id not in state.drone_states:
        await ws.close(code=1008)  # policy violation — drone must telemeter first
        return

    await ws.accept()
    seq = 0
    try:
        while True:
            frame_bytes = await ws.receive_bytes()
            await services.submit_video_frame(drone_id, frame_bytes, seq)
            seq += 1
    except WebSocketDisconnect:
        pass
