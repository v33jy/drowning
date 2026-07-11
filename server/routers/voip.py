"""
VoIP session management endpoints
==================================
The Android app uses these to query active sessions and close them when done.
Audio itself travels over UDP (port 5005) — not through HTTP.
"""

from __future__ import annotations

from fastapi import APIRouter, HTTPException

import state

router = APIRouter(prefix="/voip", tags=["voip"])


@router.get("/sessions", summary="List all VoIP sessions")
async def list_sessions() -> list:
    return [s.to_dict() for s in state.voip_sessions.values()]


@router.get("/sessions/{session_id}", summary="Get a single VoIP session")
async def get_session(session_id: str) -> dict:
    session = state.voip_sessions.get(session_id)
    if session is None:
        raise HTTPException(status_code=404, detail="Session not found")
    return session.to_dict()


@router.delete("/sessions/{session_id}", summary="End a VoIP session")
async def end_session(session_id: str) -> dict:
    session = state.voip_sessions.get(session_id)
    if session is None:
        raise HTTPException(status_code=404, detail="Session not found")
    session.active = False
    return {"ok": True}
