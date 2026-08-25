import json
import os
from pathlib import Path

# ---------------------------------------------------------------------------
# Grid configuration — override via environment variables if needed.
# The grid divides the operation area into rows × cols cells.
# ---------------------------------------------------------------------------
_DEFAULT_LAT_MIN = 37.49625
_DEFAULT_LAT_MAX = 37.50875
_DEFAULT_LNG_MIN = 127.02212178363473
_DEFAULT_LNG_MAX = 127.03787821636527
# Paper-style square experiment scene: both coordinate spans represent the
# same physical distance at the centre latitude. A 10 x 10 subdivision keeps
# the approximately 139 m square cells while reducing the operation area to
# a field-test-friendly 1.4 km x 1.4 km.
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

# Static, map-derived search priorities.  Keep these separate from live RSS
# state: the former is an operator/configuration input, while the latter
# changes throughout a mission.
GRID_PRIORITY_MIN = 1
GRID_PRIORITY_MAX = 5
_DEFAULT_GRID_PRIORITIES_FILE = Path(__file__).with_name("grid_priorities.json")


def _load_grid_priorities(path: str | os.PathLike[str]) -> tuple[int, dict[str, int]]:
    priority_path = Path(path)
    try:
        payload = json.loads(priority_path.read_text(encoding="utf-8"))
    except FileNotFoundError as error:
        raise RuntimeError(
            f"Grid priority file does not exist: {priority_path}"
        ) from error
    except json.JSONDecodeError as error:
        raise RuntimeError(
            f"Grid priority file is not valid JSON: {priority_path}"
        ) from error

    default_priority = payload.get("default_priority", 3)
    cells = payload.get("cells", {})
    if not isinstance(default_priority, int) or not (
        GRID_PRIORITY_MIN <= default_priority <= GRID_PRIORITY_MAX
    ):
        raise RuntimeError("default_priority must be an integer between 1 and 5")
    if not isinstance(cells, dict):
        raise RuntimeError("cells must be a JSON object")

    valid_cell_ids = {
        f"{chr(65 + row)}{col}"
        for row in range(GRID_ROWS)
        for col in range(GRID_COLS)
    }
    unknown = set(cells) - valid_cell_ids
    if unknown:
        raise RuntimeError(
            "Grid priority file contains unknown cells: "
            + ", ".join(sorted(unknown))
        )
    for cell_id, priority in cells.items():
        if not isinstance(priority, int) or not (
            GRID_PRIORITY_MIN <= priority <= GRID_PRIORITY_MAX
        ):
            raise RuntimeError(
                f"Priority for {cell_id} must be an integer between 1 and 5"
            )
    return default_priority, cells


_configured_priorities_file = os.getenv("GRID_PRIORITIES_FILE")
GRID_PRIORITIES_FILE: str | None = (
    _configured_priorities_file
    or (str(_DEFAULT_GRID_PRIORITIES_FILE) if _uses_default_grid else None)
)
if GRID_PRIORITIES_FILE is None:
    GRID_DEFAULT_PRIORITY, GRID_PRIORITIES = 3, {}
else:
    GRID_DEFAULT_PRIORITY, GRID_PRIORITIES = _load_grid_priorities(
        GRID_PRIORITIES_FILE
    )


def grid_priority(cell_id: str) -> int:
    return GRID_PRIORITIES.get(cell_id, GRID_DEFAULT_PRIORITY)

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
SEARCH_CANDIDATE_MIN_SCORE: float = min(
    1.0, max(0.0, float(os.getenv("SEARCH_CANDIDATE_MIN_SCORE", "0.55")))
)
SEARCH_RSS_FLOOR_DBM: float = float(os.getenv("SEARCH_RSS_FLOOR_DBM", "-100"))
SEARCH_RSS_CEILING_DBM: float = float(os.getenv("SEARCH_RSS_CEILING_DBM", "-40"))

# Maximum number of detection events kept in memory for late-joining clients.
MAX_DETECTIONS: int = 50

# Raw RSS measurements retained for search-history analysis. This remains
# in-memory for the MVP, but is deliberately bounded so a long-running server
# cannot grow without limit.
MAX_SIGNAL_READINGS: int = max(
    1, int(os.getenv("MAX_SIGNAL_READINGS", "10000"))
)

# Set this when MediaMTX is not hosted alongside the API server. When omitted,
# the detection endpoint derives a client-reachable URL from the request host.
MEDIAMTX_WHEP_URL: str | None = os.getenv("MEDIAMTX_WHEP_URL")
MEDIAMTX_WHEP_PORT: int = int(os.getenv("MEDIAMTX_WHEP_PORT", "8889"))
