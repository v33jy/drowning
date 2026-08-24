"""
Detection event endpoint
========================
The FPGA fires a hardware interrupt when it identifies a survivor signal.
The drone-side PC translates that interrupt into a POST here.
"""

from __future__ import annotations

from fastapi import APIRouter, Request

import config
import services
import state
from models import DetectionEvent

router = APIRouter(prefix="/detection", tags=["detection"])


@router.post("", summary="Report a survivor detection event from FPGA")
async def report_detection(event: DetectionEvent, request: Request) -> dict:
    host = request.url.hostname or "localhost"
    if ":" in host:
        host = f"[{host}]"
    default_stream_url = (
        f"http://{host}:{config.MEDIAMTX_WHEP_PORT}/drone/whep"
    )
    entry = await services.report_detection(event, default_stream_url)
    return {"ok": True, "detection_id": entry["detection_id"]}


@router.get("", summary="List recent detections (debug)")
async def list_detections() -> list:
    return list(state.detections)
