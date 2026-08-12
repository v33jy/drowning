import os

# ---------------------------------------------------------------------------
# Grid configuration — override via environment variables if needed.
# The grid divides the operation area into rows × cols cells.
# ---------------------------------------------------------------------------
LAT_MIN: float = float(os.getenv("GRID_LAT_MIN", "37.490"))
LAT_MAX: float = float(os.getenv("GRID_LAT_MAX", "37.515"))
LNG_MIN: float = float(os.getenv("GRID_LNG_MIN", "127.020"))
LNG_MAX: float = float(os.getenv("GRID_LNG_MAX", "127.040"))
GRID_ROWS: int = int(os.getenv("GRID_ROWS", "10"))
GRID_COLS: int = int(os.getenv("GRID_COLS", "10"))

# Legacy RSS display range retained for scenario and client compatibility.
RSS_MIN: float = float(os.getenv("RSS_MIN", "-100.0"))
RSS_MAX: float = float(os.getenv("RSS_MAX", "-40.0"))

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
