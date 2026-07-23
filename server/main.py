"""
Disaster Drone Control — FastAPI server
========================================
Entry point.  Run with:

    uvicorn main:app --host 0.0.0.0 --port 8000 --reload

Ports
-----
  8000 TCP  — HTTP REST + WebSocket (FastAPI / uvicorn)
  5005 UDP  — VoIP audio relay

WebSocket message types sent to the Android app
------------------------------------------------
init          — full state snapshot sent immediately on connection
drone_update  — single drone's telemetry changed
heatmap_update — full heatmap after any RSS reading
detection     — survivor detected; includes voip_session_id for the app to open the call
video_frame   — camera frame relayed from the drone's video WebSocket stream (no history kept)
"""

from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

import state
from routers import detection, drones, meta, signals, video, voip, websocket
from voip.relay import start_relay

logging.basicConfig(level=logging.INFO, format="%(levelname)s  %(name)s  %(message)s")


@asynccontextmanager
async def lifespan(_app: FastAPI):
    transport = await start_relay(state.voip_sessions)
    yield
    transport.close()


app = FastAPI(
    title="Disaster Drone Control Server",
    description="Real-time backend for multi-drone relay rescue system",
    version="1.0.0",
    lifespan=lifespan,
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
app.include_router(voip.router)
app.include_router(meta.router)
app.include_router(websocket.router)
