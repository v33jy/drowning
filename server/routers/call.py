"""WebRTC signaling relay. Audio flows directly between the two clients."""

from __future__ import annotations

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

import state

router = APIRouter(tags=["calls"])


@router.websocket("/survivors/listen")
async def listen_for_calls(ws: WebSocket) -> None:
    await ws.accept()
    state.survivor_waiting.append(ws)
    try:
        while True:
            message = await ws.receive()
            if message["type"] == "websocket.disconnect":
                break
    except WebSocketDisconnect:
        pass
    finally:
        if ws in state.survivor_waiting:
            state.survivor_waiting.remove(ws)


async def _relay(ws: WebSocket, session_id: str, role: str) -> None:
    session = state.call_sessions.get(session_id)
    if session is None:
        await ws.close(code=1008)
        return

    await ws.accept()
    if role == "control":
        session.control_ws = ws
    else:
        session.survivor_ws = ws

    try:
        while True:
            message = await ws.receive_json()
            peer = session.survivor_ws if role == "control" else session.control_ws
            if peer is not None:
                await peer.send_json(message)
            if message.get("type") == "call-end":
                session.active = False
                break
    except WebSocketDisconnect:
        pass
    finally:
        if role == "control" and session.control_ws is ws:
            session.control_ws = None
        elif role == "survivor" and session.survivor_ws is ws:
            session.survivor_ws = None


@router.websocket("/calls/{session_id}/control")
async def control_call(ws: WebSocket, session_id: str) -> None:
    await _relay(ws, session_id, "control")


@router.websocket("/calls/{session_id}/survivor")
async def survivor_call(ws: WebSocket, session_id: str) -> None:
    await _relay(ws, session_id, "survivor")
