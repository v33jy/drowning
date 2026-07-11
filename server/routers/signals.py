"""
Signal / heatmap endpoint
=========================
The drone-side PC posts an RSS reading after each sweep.
"""

from __future__ import annotations

from fastapi import APIRouter, Path

import services
from models import SignalReading

router = APIRouter(prefix="/drones", tags=["signals"])


@router.post("/{drone_id}/signal", summary="Submit an RSS reading for the drone's current cell")
async def submit_signal(
    reading: SignalReading,
    drone_id: int = Path(..., ge=1),
) -> dict:
    cell_id = await services.submit_signal(drone_id, reading)
    return {"ok": True, "cell_id": cell_id}
