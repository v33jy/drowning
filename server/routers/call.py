"""WebRTC signaling relay. Audio flows directly between the two clients."""

from __future__ import annotations

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

import state

router = APIRouter(tags=["calls"])


@router.websocket("/survivors/listen")
async def listen_for_calls(ws: WebSocket) -> None:
    await ws.accept()
    state.survivor_waiting.append(ws)
    pending_session = max(
        (
            session
            for session in state.call_sessions.values()
            if session.active
            and session.control_ws is not None
            and session.survivor_ws is None
        ),
        key=lambda session: session.created_at,
        default=None,
    )
    if pending_session is not None:
        await ws.send_json(
            {"type": "incoming_call", "session_id": pending_session.session_id}
        )
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
        if session.survivor_ws is None and state.survivor_waiting:
            survivor_listener = state.survivor_waiting[0]
            try:
                await survivor_listener.send_json(
                    {"type": "incoming_call", "session_id": session_id}
                )
            except RuntimeError:
                if survivor_listener in state.survivor_waiting:
                    state.survivor_waiting.remove(survivor_listener)
    else:
        session.survivor_ws = ws

    # Negotiate only after both reconnecting peers have joined. Otherwise an
    # early WebRTC offer would be dropped while the other socket is absent.
    if session.control_ws is not None and session.survivor_ws is not None:
        await session.control_ws.send_json({"type": "peer-ready"})

    ended_normally = False
    try:
        while True:
            message = await ws.receive_json()
            peer = session.survivor_ws if role == "control" else session.control_ws
            if peer is not None:
                await peer.send_json(message)
            if message.get("type") == "call-end":
                session.active = False
                ended_normally = True
                break
    except WebSocketDisconnect:
        pass
    finally:
        removed_current_peer = False
        if role == "control" and session.control_ws is ws:
            session.control_ws = None
            removed_current_peer = True
        elif role == "survivor" and session.survivor_ws is ws:
            session.survivor_ws = None
            removed_current_peer = True

        # A signaling socket can disappear before WebRTC reports a failed ICE
        # state. Notify the remaining client so both sides enter the same
        # reconnect flow immediately. Explicit call termination is already
        # relayed above and must not be treated as a transient failure.
        if removed_current_peer and not ended_normally and session.active:
            peer = session.survivor_ws if role == "control" else session.control_ws
            if peer is not None:
                try:
                    await peer.send_json({"type": "peer-disconnected"})
                except (RuntimeError, WebSocketDisconnect):
                    pass


@router.websocket("/calls/{session_id}/control")
async def control_call(ws: WebSocket, session_id: str) -> None:
    await _relay(ws, session_id, "control")


@router.websocket("/calls/{session_id}/survivor")
async def survivor_call(ws: WebSocket, session_id: str) -> None:
    await _relay(ws, session_id, "survivor")
