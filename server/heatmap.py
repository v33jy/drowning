"""
Heatmap module
==============
Responsibilities:
  1. Maintain a grid of cells that cover the operation area.
  2. Accept RSS readings from drones and update the corresponding cell.
  3. Derive an operational search status from repeated RSS observations.
  4. Provide a snapshot of all cell states for broadcast / init payloads.

Design decisions
----------------
* Pure in-memory — no I/O.  All locking is handled by the caller (state.py).
* `cell_id` format: row letter + column number, e.g. "A0", "C7".
  Rows increase southward (lat_min → lat_max), columns increase eastward.
* Unscanned cells are included in snapshots with status="unscanned" and
  color="#404040" so the Android app always has the full grid.
"""

from __future__ import annotations

import statistics
import time
from collections import deque
from dataclasses import dataclass, field
from typing import Optional

import config


# ---------------------------------------------------------------------------
# Grid helpers
# ---------------------------------------------------------------------------

def _cell_id(row: int, col: int) -> str:
    return f"{chr(65 + row)}{col}"


def cell_bounds(row: int, col: int) -> dict:
    """Return the lat/lng bounding box of a cell — used by the app to draw overlays."""
    row_h = (config.LAT_MAX - config.LAT_MIN) / config.GRID_ROWS
    col_w = (config.LNG_MAX - config.LNG_MIN) / config.GRID_COLS
    return {
        "lat_min": config.LAT_MIN + row * row_h,
        "lat_max": config.LAT_MIN + (row + 1) * row_h,
        "lng_min": config.LNG_MIN + col * col_w,
        "lng_max": config.LNG_MIN + (col + 1) * col_w,
    }


def latlng_to_cell_id(lat: float, lng: float) -> Optional[str]:
    """Convert a lat/lng coordinate to a cell_id, or None if out of bounds."""
    if not (config.LAT_MIN <= lat <= config.LAT_MAX and config.LNG_MIN <= lng <= config.LNG_MAX):
        return None
    row = int((lat - config.LAT_MIN) / (config.LAT_MAX - config.LAT_MIN) * config.GRID_ROWS)
    col = int((lng - config.LNG_MIN) / (config.LNG_MAX - config.LNG_MIN) * config.GRID_COLS)
    row = min(row, config.GRID_ROWS - 1)
    col = min(col, config.GRID_COLS - 1)
    return _cell_id(row, col)


def grid_definition() -> list[dict]:
    """Return the full grid with cell IDs and lat/lng bounds.

    Called once by the Android app on startup so it knows how to render each cell.
    """
    cells = []
    for row in range(config.GRID_ROWS):
        for col in range(config.GRID_COLS):
            cells.append({"cell_id": _cell_id(row, col), "bounds": cell_bounds(row, col)})
    return cells


# ---------------------------------------------------------------------------
# Heatmap state
# ---------------------------------------------------------------------------

_STATUS_COLORS = {
    "unscanned": "#404040",
    "scanning": "#1976D2",
    "needs_recheck": "#F57C00",
}


@dataclass
class CellSignalSummary:
    """Mutable aggregation state for one search cell.

    Raw measurements remain in ``state.signal_readings``. This class keeps
    only the bounded values required for the live operational summary.
    """

    cell_id: str
    recent_rss: deque[float] = field(
        default_factory=lambda: deque(maxlen=config.SEARCH_RECENT_WINDOW)
    )
    drone_ids: set[int] = field(default_factory=set)
    sample_count: int = 0
    latest_rss_dbm: Optional[float] = None
    peak_rss_dbm: Optional[float] = None
    last_updated: Optional[float] = None
    latest_drone_id: Optional[int] = None

    def record(
        self,
        drone_id: int,
        rss_dbm: float,
        measured_at: Optional[float] = None,
    ) -> None:
        self.recent_rss.append(rss_dbm)
        self.drone_ids.add(drone_id)
        self.sample_count += 1
        self.peak_rss_dbm = (
            rss_dbm
            if self.peak_rss_dbm is None
            else max(self.peak_rss_dbm, rss_dbm)
        )
        timestamp = measured_at if measured_at is not None else time.time()
        if self.last_updated is None or timestamp >= self.last_updated:
            self.latest_rss_dbm = rss_dbm
            self.latest_drone_id = drone_id
            self.last_updated = timestamp

    @property
    def representative_rss_dbm(self) -> Optional[float]:
        if not self.recent_rss:
            return None
        return round(statistics.median(self.recent_rss), 1)

    @property
    def average_rss_dbm(self) -> Optional[float]:
        if not self.recent_rss:
            return None
        return round(statistics.fmean(self.recent_rss), 1)

    @property
    def strong_signal_count(self) -> int:
        return sum(
            rss >= config.SEARCH_RECHECK_RSS_DBM for rss in self.recent_rss
        )

    @property
    def status(self) -> str:
        if self.sample_count == 0:
            return "unscanned"
        if self.strong_signal_count >= config.SEARCH_RECHECK_MIN_SAMPLES:
            return "needs_recheck"
        return "scanning"

    @property
    def status_reason(self) -> str:
        if self.status == "unscanned":
            return "no_measurements"
        if self.status == "needs_recheck":
            return "repeated_strong_signal"
        return "insufficient_repeated_signal"

    def to_dict(self) -> dict:
        representative = self.representative_rss_dbm
        return {
            "cell_id": self.cell_id,
            "drone_id": self.latest_drone_id,
            "rss_dbm": representative,
            "latest_rss_dbm": self.latest_rss_dbm,
            "average_rss_dbm": self.average_rss_dbm,
            "peak_rss_dbm": self.peak_rss_dbm,
            "sample_count": self.sample_count,
            "drone_count": len(self.drone_ids),
            "strong_signal_count": self.strong_signal_count,
            "color": _STATUS_COLORS[self.status],
            "status": self.status,
            "status_reason": self.status_reason,
            "last_updated": self.last_updated,
        }


class HeatmapState:
    """Maintains a live search summary derived from raw RSS observations."""

    def __init__(self) -> None:
        self._cells: dict[str, CellSignalSummary] = {
            _cell_id(r, c): CellSignalSummary(cell_id=_cell_id(r, c))
            for r in range(config.GRID_ROWS)
            for c in range(config.GRID_COLS)
        }

    def update(
        self,
        cell_id: str,
        drone_id: int,
        rss_dbm: float,
        measured_at: Optional[float] = None,
    ) -> None:
        """Record an RSS reading for an existing grid cell.

        Raises ValueError for unknown cell_ids so callers get a clear error
        rather than silently growing the grid with phantom cells.
        """
        if cell_id not in self._cells:
            raise ValueError(f"Unknown cell_id '{cell_id}'. Must be within the configured grid.")
        self._cells[cell_id].record(drone_id, rss_dbm, measured_at)

    def snapshot(self) -> list[dict]:
        """Return all cell states as a list, suitable for JSON serialisation."""
        return [cell.to_dict() for cell in self._cells.values()]
