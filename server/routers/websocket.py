"""
WebSocket — persistent connection with the control app.
"""

from __future__ import annotations

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

import state
from models import WsMessage

router = APIRouter()


@router.websocket("/ws/control")
async def websocket_control(ws: WebSocket) -> None:
    await state.manager.connect(ws)

    # Send the full current state so the app is up-to-date immediately.
    await ws.send_json(
        WsMessage.init(
            drones=list(state.drone_states.values()),
            heatmap=state.heatmap.snapshot(),
            detections=list(state.detections),
        )
    )

    try:
        # Keep the connection alive.  The app may send pings as plain text;
        # we simply discard them — all meaningful traffic is server → client.
        while True:
            await ws.receive_text()
    except WebSocketDisconnect:
        state.manager.disconnect(ws)
