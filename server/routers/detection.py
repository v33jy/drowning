"""
Detection event endpoint
========================
The FPGA fires a hardware interrupt when it identifies a survivor signal.
The drone-side PC translates that interrupt into a POST here.
"""

from __future__ import annotations

from fastapi import APIRouter

import services
import state
from models import DetectionEvent

router = APIRouter(prefix="/detection", tags=["detection"])


@router.post("", summary="Report a survivor detection event from FPGA")
async def report_detection(event: DetectionEvent) -> dict:
    entry = await services.report_detection(event)
    return {"ok": True, "voip_session_id": entry["voip_session_id"]}


@router.get("", summary="List recent detections (debug)")
async def list_detections() -> list:
    return list(state.detections)
