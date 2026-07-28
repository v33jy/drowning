"""
Shared application state — single source of truth for the server process.

All mutation happens inside route handlers driven by asyncio (single-threaded).
Explicit locks guard only multi-step read-modify-write sequences that span an
await boundary, where another coroutine could otherwise observe inconsistent state.
"""

from __future__ import annotations

import asyncio
import collections

import config
from heatmap import HeatmapState
from ws_manager import ConnectionManager

drone_states: dict[int, dict] = {}

heatmap = HeatmapState()

detections: collections.deque[dict] = collections.deque(maxlen=config.MAX_DETECTIONS)

manager = ConnectionManager()

lock = asyncio.Lock()
