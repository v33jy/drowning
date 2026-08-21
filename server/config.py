import json
import os

# ---------------------------------------------------------------------------
# Grid configuration — override via environment variables if needed.
# The grid divides the operation area into rows × cols cells.
# ---------------------------------------------------------------------------
_DEFAULT_LAT_MIN = 37.490
_DEFAULT_LAT_MAX = 37.515
_DEFAULT_LNG_MIN = 127.020
_DEFAULT_LNG_MAX = 127.040
_DEFAULT_GRID_ROWS = 10
_DEFAULT_GRID_COLS = 10

LAT_MIN: float = float(os.getenv("GRID_LAT_MIN", str(_DEFAULT_LAT_MIN)))
LAT_MAX: float = float(os.getenv("GRID_LAT_MAX", str(_DEFAULT_LAT_MAX)))
LNG_MIN: float = float(os.getenv("GRID_LNG_MIN", str(_DEFAULT_LNG_MIN)))
LNG_MAX: float = float(os.getenv("GRID_LNG_MAX", str(_DEFAULT_LNG_MAX)))
GRID_ROWS: int = int(os.getenv("GRID_ROWS", str(_DEFAULT_GRID_ROWS)))
GRID_COLS: int = int(os.getenv("GRID_COLS", str(_DEFAULT_GRID_COLS)))

# Responder-facing names for grid cells. Configure these during operation-area
# setup so the UI can use stable landmarks without depending on live geocoding.
_uses_default_grid = (
    LAT_MIN == _DEFAULT_LAT_MIN
    and LAT_MAX == _DEFAULT_LAT_MAX
    and LNG_MIN == _DEFAULT_LNG_MIN
    and LNG_MAX == _DEFAULT_LNG_MAX
    and GRID_ROWS == _DEFAULT_GRID_ROWS
    and GRID_COLS == _DEFAULT_GRID_COLS
)
_configured_landmarks = os.getenv("GRID_LANDMARKS")


def _load_grid_landmarks(
    configured_landmarks: str | None,
    uses_default_grid: bool,
) -> dict[str, str]:
    if configured_landmarks is not None:
        return json.loads(configured_landmarks)
    if not uses_default_grid:
        return {}

    # Keep several visually distinctive field references across the default
    # operation area.  A single station anchor makes every cell read like a
    # transit direction and is difficult for responders to place on a map.
    return {
        "F2": "교보타워 인근",
        "E5": "국기원 인근",
    }


GRID_LANDMARKS = _load_grid_landmarks(_configured_landmarks, _uses_default_grid)

# Preliminary search-area classification. These are operational tuning values,
# not validated probabilities; field tests should calibrate them per radio and
# environment without requiring code changes.
SEARCH_RECENT_WINDOW: int = max(1, int(os.getenv("SEARCH_RECENT_WINDOW", "10")))
SEARCH_RECHECK_RSS_DBM: float = float(
    os.getenv("SEARCH_RECHECK_RSS_DBM", "-65.0")
)
SEARCH_RECHECK_MIN_SAMPLES: int = max(
    1,
    min(
        SEARCH_RECENT_WINDOW,
        int(os.getenv("SEARCH_RECHECK_MIN_SAMPLES", "3")),
    ),
)

# Maximum number of detection events kept in memory for late-joining clients.
MAX_DETECTIONS: int = 50

# Raw RSS measurements retained for search-history analysis. This remains
# in-memory for the MVP, but is deliberately bounded so a long-running server
# cannot grow without limit.
MAX_SIGNAL_READINGS: int = max(
    1, int(os.getenv("MAX_SIGNAL_READINGS", "10000"))
)

# Camera review history. The live stream can be much faster, but only a small
# number of frames per second is retained for operational review. Bookmarks
# preserve the configured interval around the moment a cell first becomes a
# recheck area.
VIDEO_HISTORY_SAMPLE_INTERVAL: float = max(
    0.1, float(os.getenv("VIDEO_HISTORY_SAMPLE_INTERVAL", "1.0"))
)
VIDEO_BOOKMARK_PRE_SECONDS: float = max(
    0.0, float(os.getenv("VIDEO_BOOKMARK_PRE_SECONDS", "10.0"))
)
VIDEO_BOOKMARK_POST_SECONDS: float = max(
    0.0, float(os.getenv("VIDEO_BOOKMARK_POST_SECONDS", "10.0"))
)
MAX_VIDEO_BOOKMARKS: int = max(
    1, int(os.getenv("MAX_VIDEO_BOOKMARKS", "50"))
)
