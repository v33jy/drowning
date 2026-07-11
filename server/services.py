"""
Service layer
=============
Owns "what happens" when telemetry/signal/detection/video events come in —
state mutation plus the WebSocket broadcast that follows it. Routers stay
thin: parse the request, call the matching function here, shape the response.
"""

from __future__ import annotations

import time

from fastapi import HTTPException

import state
from heatmap import latlng_to_cell_id
from models import DetectionEvent, DroneTelemetry, SignalReading, VideoFrame, WsMessage
from voip.session import VoIPSession


async def submit_telemetry(drone_id: int, telemetry: DroneTelemetry) -> dict:
    entry = {
        "drone_id": drone_id,
        **telemetry.model_dump(),
        "cell_id": latlng_to_cell_id(telemetry.lat, telemetry.lng),
        "last_updated": time.time(),
    }
    # Single dict assignment needs no lock — no await between read and write.
    state.drone_states[drone_id] = entry
    await state.manager.broadcast(WsMessage.drone_update(entry))
    return entry


async def submit_signal(drone_id: int, reading: SignalReading) -> str:
    """Update the heatmap cell the drone is currently in. Returns the cell_id.

    Why post to /drones/{id}/signal instead of /cells/{id}/signal:
      The PC already knows the drone_id; computing the cell_id from lat/lng is
      server-side logic that should not leak into the drone control code.
    """
    async with state.lock:
        drone = state.drone_states.get(drone_id)
        if drone is None:
            raise HTTPException(
                status_code=404,
                detail=f"Drone {drone_id} has not sent telemetry yet — cell unknown.",
            )
        cell_id = drone.get("cell_id")
        if cell_id is None:
            raise HTTPException(
                status_code=422,
                detail=f"Drone {drone_id} is outside the configured grid area.",
            )
        state.heatmap.update(cell_id, drone_id, reading.rss_dbm)
        snapshot = state.heatmap.snapshot()

    await state.manager.broadcast(WsMessage.heatmap_update(snapshot))
    return cell_id


async def report_detection(event: DetectionEvent) -> dict:
    """Record a survivor detection and open a VoIP session for it.

    The session is created immediately (before any await) so the app can open
    the call channel without a round-trip delay.
    """
    session = VoIPSession(drone_id=event.drone_id, cell_id=event.cell_id)

    entry = {
        **event.model_dump(),
        "timestamp": time.time(),
        "voip_session_id": session.session_id,
    }

    async with state.lock:
        state.detections.append(entry)
        state.voip_sessions[session.session_id] = session

    await state.manager.broadcast(WsMessage.detection(entry))
    return entry


async def submit_video_frame(drone_id: int, frame: VideoFrame) -> None:
    if drone_id not in state.drone_states:
        raise HTTPException(
            status_code=404,
            detail=f"Drone {drone_id} has not sent telemetry yet.",
        )
    await state.manager.broadcast(WsMessage.video_frame(drone_id, frame.frame_b64, frame.seq))
