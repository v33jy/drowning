"""
Shared application state — single source of truth for the server process.

All mutation happens inside route handlers driven by asyncio (single-threaded).
Explicit locks guard only multi-step read-modify-write sequences that span an
await boundary, where another coroutine could otherwise observe inconsistent state.
"""

from __future__ import annotations

import asyncio
import collections
from dataclasses import dataclass
from typing import Optional

from fastapi import WebSocket

import config
from heatmap import HeatmapState
from ws_manager import ConnectionManager

drone_states: dict[int, dict] = {}

heatmap = HeatmapState()

detections: collections.deque[dict] = collections.deque(maxlen=config.MAX_DETECTIONS)

# Source-of-truth RSS observations. The heatmap is only a derived, latest-value
# view; retaining the original position/time samples enables later repeat,
# trend, and revisit analysis without changing today's app payloads.
signal_readings: collections.deque[dict] = collections.deque(
    maxlen=config.MAX_SIGNAL_READINGS
)
signal_readings_by_id: dict[tuple[int, str], dict] = {}

# Sampled JPEG frames and RSS-triggered review bookmarks. Both are bounded;
# raw live-stream frames are never accumulated indefinitely.
video_frame_buffers: dict[int, collections.deque[dict]] = {}
video_last_sampled_at: dict[int, float] = {}
video_bookmarks: collections.deque[dict] = collections.deque(
    maxlen=config.MAX_VIDEO_BOOKMARKS
)

manager = ConnectionManager()

lock = asyncio.Lock()


@dataclass
class CallSession:
    session_id: str
    drone_id: int
    cell_id: str
    created_at: float
    active: bool = True
    control_ws: Optional[WebSocket] = None
    survivor_ws: Optional[WebSocket] = None


call_sessions: dict[str, CallSession] = {}

# MVP pairs each detection with the single listening survivor app.
survivor_waiting: list[WebSocket] = []
