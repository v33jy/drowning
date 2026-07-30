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

# RSS range used for colour mapping (dBm).
RSS_MIN: float = float(os.getenv("RSS_MIN", "-100.0"))
RSS_MAX: float = float(os.getenv("RSS_MAX", "-40.0"))

# Maximum number of detection events kept in memory for late-joining clients.
MAX_DETECTIONS: int = 50
