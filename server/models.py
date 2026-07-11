from __future__ import annotations
from typing import Optional
from pydantic import BaseModel, Field


class DroneTelemetry(BaseModel):
    lat: float
    lng: float
    altitude: float = Field(ge=0)
    battery: int = Field(ge=0, le=100)
    status: str = "active"  # active | returning | lost


class SignalReading(BaseModel):
    rss_dbm: float = Field(le=0, description="Received signal strength in dBm (negative value)")


class DetectionEvent(BaseModel):
    drone_id: int
    cell_id: str
    rss_dbm: float
    stream_url: Optional[str] = None


class VideoFrame(BaseModel):
    frame_b64: str = Field(description="Single video frame, base64-encoded (JPEG/PNG)")
    seq: int = Field(ge=0, default=0)


# ---------------------------------------------------------------------------
# WebSocket message envelopes sent to the Android app.
# ---------------------------------------------------------------------------
class WsMessage:
    @staticmethod
    def init(drones: list, heatmap: list, detections: list) -> dict:
        return {"type": "init", "data": {"drones": drones, "heatmap": heatmap, "detections": detections}}

    @staticmethod
    def drone_update(drone: dict) -> dict:
        return {"type": "drone_update", "data": drone}

    @staticmethod
    def heatmap_update(cells: list) -> dict:
        return {"type": "heatmap_update", "data": cells}

    @staticmethod
    def detection(event: dict) -> dict:
        return {"type": "detection", "data": event}

    @staticmethod
    def video_frame(drone_id: int, frame_b64: str, seq: int) -> dict:
        return {"type": "video_frame", "data": {"drone_id": drone_id, "frame_b64": frame_b64, "seq": seq}}
