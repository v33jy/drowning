"""Bounded camera history linked to RSS-driven search-area decisions."""

from __future__ import annotations

import collections
import time
import uuid

import config
import state


def _buffer_maxlen() -> int:
    seconds = config.VIDEO_BOOKMARK_PRE_SECONDS + 2
    return max(1, int(seconds / config.VIDEO_HISTORY_SAMPLE_INTERVAL) + 1)


def _frame_metadata(frame: dict) -> dict:
    return {
        "seq": frame["seq"],
        "captured_at": frame["captured_at"],
        "cell_id": frame["cell_id"],
        "lat": frame["lat"],
        "lng": frame["lng"],
        "altitude": frame["altitude"],
    }


def _find_bookmark(bookmark_id: str) -> dict | None:
    return next(
        (
            bookmark
            for bookmark in state.video_bookmarks
            if bookmark["bookmark_id"] == bookmark_id
        ),
        None,
    )


def _bookmark_metadata(bookmark: dict) -> dict:
    metadata = {key: value for key, value in bookmark.items() if key != "frames"}
    frames = bookmark["frames"]
    return {
        **metadata,
        "frame_count": len(frames),
        "frames": [_frame_metadata(frame) for frame in frames],
    }


def _append_to_active_bookmarks(drone_id: int, frame: dict, now: float) -> None:
    for bookmark in state.video_bookmarks:
        if bookmark["drone_id"] != drone_id or bookmark["complete"]:
            continue
        if now > bookmark["ends_at"]:
            bookmark["complete"] = True
            continue
        bookmark["frames"].append(frame)


def retain_frame(
    drone_id: int,
    frame_bytes: bytes,
    seq: int,
    captured_at: float | None = None,
) -> None:
    """Sample a live JPEG and append it to active post-event bookmarks."""
    now = captured_at if captured_at is not None else time.time()
    previous = state.video_last_sampled_at.get(drone_id)
    if previous is not None and now - previous < config.VIDEO_HISTORY_SAMPLE_INTERVAL:
        return

    drone = state.drone_states.get(drone_id, {})
    frame = {
        "seq": seq,
        "captured_at": now,
        "cell_id": drone.get("cell_id"),
        "lat": drone.get("lat"),
        "lng": drone.get("lng"),
        "altitude": drone.get("altitude"),
        "jpeg": frame_bytes,
    }
    buffer = state.video_frame_buffers.setdefault(
        drone_id, collections.deque(maxlen=_buffer_maxlen())
    )
    buffer.append(frame)
    state.video_last_sampled_at[drone_id] = now

    _append_to_active_bookmarks(drone_id, frame, now)


def create_recheck_bookmark(measurement: dict) -> dict:
    """Preserve buffered frames before an RSS recheck decision."""
    triggered_at = measurement["received_at"]
    starts_at = triggered_at - config.VIDEO_BOOKMARK_PRE_SECONDS
    frames = [
        frame
        for frame in state.video_frame_buffers.get(measurement["drone_id"], ())
        if frame["captured_at"] >= starts_at
    ]
    bookmark = {
        "bookmark_id": str(uuid.uuid4()),
        "drone_id": measurement["drone_id"],
        "cell_id": measurement["cell_id"],
        "measurement_id": measurement["measurement_id"],
        "rss_dbm": measurement["rss_dbm"],
        "triggered_at": triggered_at,
        "starts_at": starts_at,
        "ends_at": triggered_at + config.VIDEO_BOOKMARK_POST_SECONDS,
        "complete": config.VIDEO_BOOKMARK_POST_SECONDS == 0,
        "frames": frames,
    }
    state.video_bookmarks.append(bookmark)
    return bookmark


def list_bookmarks(cell_id: str | None = None) -> list[dict]:
    return [
        _bookmark_metadata(bookmark)
        for bookmark in reversed(state.video_bookmarks)
        if cell_id is None or bookmark["cell_id"] == cell_id
    ]


def get_frame(bookmark_id: str, frame_index: int) -> bytes | None:
    bookmark = _find_bookmark(bookmark_id)
    if bookmark is None or not 0 <= frame_index < len(bookmark["frames"]):
        return None
    return bookmark["frames"][frame_index]["jpeg"]
