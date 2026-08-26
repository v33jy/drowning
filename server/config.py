import json
import math
import os
from pathlib import Path
from urllib.parse import urlparse


def _env_int(name: str, default: int, *, minimum: int | None = None) -> int:
    raw = os.getenv(name, str(default))
    try:
        value = int(raw)
    except ValueError as error:
        raise RuntimeError(f"{name} must be an integer, got {raw!r}") from error
    if minimum is not None and value < minimum:
        raise RuntimeError(f"{name} must be at least {minimum}, got {value}")
    return value


def _env_float(name: str, default: float) -> float:
    raw = os.getenv(name, str(default))
    try:
        value = float(raw)
    except ValueError as error:
        raise RuntimeError(f"{name} must be a number, got {raw!r}") from error
    if not math.isfinite(value):
        raise RuntimeError(f"{name} must be a finite number, got {raw!r}")
    return value


def _env_origins(name: str = "CORS_ORIGINS") -> list[str]:
    raw = os.getenv(name, "*")
    origins = [origin.strip() for origin in raw.split(",") if origin.strip()]
    if not origins:
        raise RuntimeError(f"{name} must contain at least one origin")
    for origin in origins:
        if origin == "*":
            continue
        parsed = urlparse(origin)
        if parsed.scheme not in {"http", "https"} or not parsed.netloc:
            raise RuntimeError(
                f"{name} contains an invalid HTTP(S) origin: {origin!r}"
            )
    return origins

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

LAT_MIN: float = _env_float("GRID_LAT_MIN", _DEFAULT_LAT_MIN)
LAT_MAX: float = _env_float("GRID_LAT_MAX", _DEFAULT_LAT_MAX)
LNG_MIN: float = _env_float("GRID_LNG_MIN", _DEFAULT_LNG_MIN)
LNG_MAX: float = _env_float("GRID_LNG_MAX", _DEFAULT_LNG_MAX)
GRID_ROWS: int = _env_int("GRID_ROWS", _DEFAULT_GRID_ROWS, minimum=1)
GRID_COLS: int = _env_int("GRID_COLS", _DEFAULT_GRID_COLS, minimum=1)
if LAT_MIN >= LAT_MAX:
    raise RuntimeError("GRID_LAT_MIN must be less than GRID_LAT_MAX")
if LNG_MIN >= LNG_MAX:
    raise RuntimeError("GRID_LNG_MIN must be less than GRID_LNG_MAX")

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
        try:
            landmarks = json.loads(configured_landmarks)
        except json.JSONDecodeError as error:
            raise RuntimeError("GRID_LANDMARKS must be a valid JSON object") from error
        if not isinstance(landmarks, dict) or not all(
            isinstance(key, str) and isinstance(value, str)
            for key, value in landmarks.items()
        ):
            raise RuntimeError(
                "GRID_LANDMARKS must be a JSON object mapping cell IDs to string labels"
            )
        return landmarks
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
    except PermissionError as error:
        raise RuntimeError(
            f"Grid priority file is not readable (permission denied): {priority_path}"
        ) from error
    except OSError as error:
        raise RuntimeError(
            f"Could not read grid priority file {priority_path}: {error}"
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
SEARCH_RECENT_WINDOW: int = _env_int("SEARCH_RECENT_WINDOW", 10, minimum=1)
SEARCH_RECHECK_RSS_DBM: float = _env_float("SEARCH_RECHECK_RSS_DBM", -65.0)
SEARCH_RECHECK_MIN_SAMPLES: int = max(
    1,
    min(
        SEARCH_RECENT_WINDOW,
        _env_int("SEARCH_RECHECK_MIN_SAMPLES", 3, minimum=1),
    ),
)
SEARCH_CANDIDATE_MIN_SCORE: float = min(
    1.0, max(0.0, _env_float("SEARCH_CANDIDATE_MIN_SCORE", 0.55))
)
SEARCH_RSS_FLOOR_DBM: float = _env_float("SEARCH_RSS_FLOOR_DBM", -100)
SEARCH_RSS_CEILING_DBM: float = _env_float("SEARCH_RSS_CEILING_DBM", -40)
if SEARCH_RSS_FLOOR_DBM >= SEARCH_RSS_CEILING_DBM:
    raise RuntimeError("SEARCH_RSS_FLOOR_DBM must be less than SEARCH_RSS_CEILING_DBM")

# Maximum number of detection events kept in memory for late-joining clients.
MAX_DETECTIONS: int = 50

# Raw RSS measurements retained for search-history analysis. This remains
# in-memory for the MVP, but is deliberately bounded so a long-running server
# cannot grow without limit.
MAX_SIGNAL_READINGS: int = _env_int("MAX_SIGNAL_READINGS", 10000, minimum=1)

# Set this when MediaMTX is not hosted alongside the API server. When omitted,
# the detection endpoint derives a client-reachable URL from the request host.
MEDIAMTX_WHEP_URL: str | None = os.getenv("MEDIAMTX_WHEP_URL")
MEDIAMTX_WHEP_PORT: int = _env_int("MEDIAMTX_WHEP_PORT", 8889, minimum=1)
if MEDIAMTX_WHEP_PORT > 65535:
    raise RuntimeError("MEDIAMTX_WHEP_PORT must be at most 65535")

CORS_ORIGINS: list[str] = _env_origins()
WS_SEND_TIMEOUT_SECONDS: float = _env_float("WS_SEND_TIMEOUT_SECONDS", 2.0)
if WS_SEND_TIMEOUT_SECONDS <= 0:
    raise RuntimeError("WS_SEND_TIMEOUT_SECONDS must be greater than 0")
