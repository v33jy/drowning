"""WebSocket connection manager — broadcasts JSON messages to all live clients."""

from __future__ import annotations

import json
import logging

from fastapi import WebSocket

logger = logging.getLogger(__name__)


class ConnectionManager:
    def __init__(self) -> None:
        self._clients: list[WebSocket] = []

    async def connect(self, ws: WebSocket) -> None:
        await ws.accept()
        self._clients.append(ws)
        logger.info("Client connected. Total: %d", len(self._clients))

    def disconnect(self, ws: WebSocket) -> None:
        # discard pattern: safe even if ws was already removed during broadcast
        try:
            self._clients.remove(ws)
        except ValueError:
            pass
        logger.info("Client disconnected. Total: %d", len(self._clients))

    async def broadcast(self, message: dict) -> None:
        """Send a message to all connected clients, silently dropping dead ones.

        Snapshots _clients before iterating so that connect/disconnect calls
        from other coroutines during the awaits inside this loop cannot cause
        concurrent-modification bugs.
        """
        if not self._clients:
            return
        payload = json.dumps(message, ensure_ascii=False)
        dead: list[WebSocket] = []
        for ws in list(self._clients):  # snapshot
            try:
                await ws.send_text(payload)
            except Exception:
                dead.append(ws)
        for ws in dead:
            try:
                self._clients.remove(ws)
            except ValueError:
                pass  # disconnect() already removed it
            logger.warning("Removed dead WebSocket client.")
