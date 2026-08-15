"""
Meta / debug endpoints
=======================
Grid definition (used once by the app on startup), full state snapshot, and
a health check — none of these belong to a specific domain router.
"""

from __future__ import annotations

from fastapi import APIRouter

import state
import video_history
from heatmap import grid_definition

router = APIRouter(tags=["meta"])


@router.get("/heatmap/grid", summary="Return cell IDs and lat/lng bounds for all grid cells")
async def get_grid() -> list:
    return grid_definition()


@router.get("/state", summary="Full server state (debug)")
async def get_state() -> dict:
    return {
        "drones": list(state.drone_states.values()),
        "heatmap": state.heatmap.snapshot(),
        "signal_readings": list(state.signal_readings),
        "detections": list(state.detections),
        "video_bookmarks": video_history.list_bookmarks(),
    }


@router.get("/health")
async def health() -> dict:
    return {"status": "ok"}
