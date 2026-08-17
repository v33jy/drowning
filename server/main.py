"""
Disaster Drone Control — FastAPI server
========================================
Entry point.  Run with:

    uvicorn main:app --host 0.0.0.0 --port 8000 --reload

Ports
-----
  8000 TCP  — HTTP REST + WebSocket (FastAPI / uvicorn)

WebSocket message types sent to the Android app
------------------------------------------------
init          — full state snapshot sent immediately on connection
drone_update  — single drone's telemetry changed
heatmap_update — full heatmap after any RSS reading
detection     — survivor detected; includes detection_id identifying the entry
video_frame   — live camera frame; sampled history is kept around RSS recheck events
"""

from __future__ import annotations

import logging

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from routers import call, detection, drones, meta, signals, video, websocket

logging.basicConfig(level=logging.INFO, format="%(levelname)s  %(name)s  %(message)s")

app = FastAPI(
    title="Disaster Drone Control Server",
    description="Real-time backend for drone-based search and rescue support",
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(drones.router)
app.include_router(signals.router)
app.include_router(detection.router)
app.include_router(video.router)
app.include_router(call.router)
app.include_router(meta.router)
app.include_router(websocket.router)
