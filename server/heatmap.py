"""
Heatmap module
==============
Responsibilities:
  1. Maintain a grid of cells that cover the operation area.
  2. Accept RSS readings from drones and update the corresponding cell.
  3. Convert RSS dBm values to hex colours (blue = weak → red = strong).
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

import colorsys
import time
from typing import Optional

import config


# ---------------------------------------------------------------------------
# Colour mapping
# ---------------------------------------------------------------------------

def rss_to_color(rss_dbm: float) -> str:
    """Map an RSS value to a hex colour string.

    Mapping uses HSV with saturation=1, value=1 and hue sliding from
    240° (blue, weak signal) down to 0° (red, strong signal).  Colours
    outside the configured range are clamped.
    """
    denominator = config.RSS_MAX - config.RSS_MIN
    if denominator == 0:
        return "#FF0000"
    ratio = max(0.0, min(1.0, (rss_dbm - config.RSS_MIN) / denominator))
    hue = (1.0 - ratio) * 240.0 / 360.0
    r, g, b = colorsys.hsv_to_rgb(hue, 1.0, 1.0)
    return f"#{int(r * 255):02X}{int(g * 255):02X}{int(b * 255):02X}"


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

_UNSCANNED_COLOR = "#404040"


class HeatmapState:
    """Stores the latest RSS reading for every cell in the grid."""

    def __init__(self) -> None:
        # Pre-populate all cells as unscanned so snapshots are always complete.
        self._cells: dict[str, dict] = {
            _cell_id(r, c): {
                "cell_id": _cell_id(r, c),
                "drone_id": None,
                "rss_dbm": None,
                "color": _UNSCANNED_COLOR,
                "status": "unscanned",
                "last_updated": None,
            }
            for r in range(config.GRID_ROWS)
            for c in range(config.GRID_COLS)
        }

    def update(self, cell_id: str, drone_id: int, rss_dbm: float) -> None:
        """Record an RSS reading for an existing grid cell.

        Raises ValueError for unknown cell_ids so callers get a clear error
        rather than silently growing the grid with phantom cells.
        """
        if cell_id not in self._cells:
            raise ValueError(f"Unknown cell_id '{cell_id}'. Must be within the configured grid.")
        self._cells[cell_id] = {
            "cell_id": cell_id,
            "drone_id": drone_id,
            "rss_dbm": rss_dbm,
            "color": rss_to_color(rss_dbm),
            "status": "active",
            "last_updated": time.time(),
        }

    def snapshot(self) -> list[dict]:
        """Return all cell states as a list, suitable for JSON serialisation."""
        return list(self._cells.values())
