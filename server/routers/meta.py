"""
Meta / debug endpoints
=======================
Grid definition (used once by the app on startup), full state snapshot, and
a health check — none of these belong to a specific domain router.
"""

from __future__ import annotations

from fastapi import APIRouter

import state
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
        "detections": list(state.detections),
    }


@router.get("/health")
async def health() -> dict:
    return {"status": "ok"}
