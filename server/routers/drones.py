"""
Drone telemetry endpoints
=========================
The drone-side PC posts position and battery status here on each telemetry cycle.
"""

from __future__ import annotations

from fastapi import APIRouter, Path

import services
import state
from models import DroneTelemetry

router = APIRouter(prefix="/drones", tags=["drones"])


@router.post("/{drone_id}/telemetry", summary="Update drone position and battery")
async def update_telemetry(
    telemetry: DroneTelemetry,
    drone_id: int = Path(..., ge=1),
) -> dict:
    # entry already includes cell_id, so return it as-is — lets the gateway
    # get cell_id for detection events without duplicating the grid math.
    return await services.submit_telemetry(drone_id, telemetry)


@router.get("", summary="List all known drones (debug)")
async def list_drones() -> list:
    return list(state.drone_states.values())
