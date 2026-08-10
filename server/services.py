"""
Service layer
=============
Owns "what happens" when telemetry/signal/detection/video events come in —
state mutation plus the WebSocket broadcast that follows it. Routers stay
thin: parse the request, call the matching function here, shape the response.
"""

from __future__ import annotations

import base64
import time
import uuid

from fastapi import HTTPException

import state
from heatmap import latlng_to_cell_id
from models import DetectionEvent, DroneTelemetry, SignalReading, WsMessage


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
    """Record a survivor detection, tagged with a unique detection_id."""
    call_session_id = str(uuid.uuid4())
    entry = {
        **event.model_dump(),
        "timestamp": time.time(),
        "detection_id": str(uuid.uuid4()),
        "call_session_id": call_session_id,
    }

    async with state.lock:
        state.detections.append(entry)
        state.call_sessions[call_session_id] = state.CallSession(
            session_id=call_session_id,
            drone_id=event.drone_id,
            cell_id=event.cell_id,
            created_at=time.time(),
        )
        survivor_ws = state.survivor_waiting[0] if state.survivor_waiting else None

    await state.manager.broadcast(WsMessage.detection(entry))
    if survivor_ws is not None:
        try:
            await survivor_ws.send_json(
                {"type": "incoming_call", "session_id": call_session_id}
            )
        except RuntimeError:
            if survivor_ws in state.survivor_waiting:
                state.survivor_waiting.remove(survivor_ws)
    return entry


async def submit_video_frame(drone_id: int, frame_bytes: bytes, seq: int) -> None:
    """frame_bytes is a single raw JPEG frame — encoding happens only on this last
    hop (server → app), so the drone → server WebSocket stays fully binary."""
    frame_b64 = base64.b64encode(frame_bytes).decode("ascii")
    await state.manager.broadcast(WsMessage.video_frame(drone_id, frame_b64, seq))
