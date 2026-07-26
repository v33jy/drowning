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
    # entry에 cell_id가 포함돼 있어 그대로 돌려줌 — 게이트웨이가 그리드 계산을
    # 따로 하지 않고 이 응답만으로 탐지 이벤트에 필요한 cell_id를 알 수 있음.
    return await services.submit_telemetry(drone_id, telemetry)


@router.get("", summary="List all known drones (debug)")
async def list_drones() -> list:
    return list(state.drone_states.values())
