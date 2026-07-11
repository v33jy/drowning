"""
Drone simulator — sends fake telemetry, RSS, and detection events to the server.

Usage:
    python3 dummy.py              # 3 drones, random movement
    python3 dummy.py --drones 5  # 5 drones
    python3 dummy.py --detect    # trigger a detection event immediately
"""

from __future__ import annotations

import argparse
import asyncio
import math
import os
import random

import httpx

BASE_URL = os.environ.get("DRONE_SERVER_URL", "http://localhost:8000")

# Grid centre and step size (matches config.py defaults)
LAT_MIN, LAT_MAX = 37.0, 37.1
LNG_MIN, LNG_MAX = 127.0, 127.1


class DroneSim:
    def __init__(self, drone_id: int):
        self.drone_id = drone_id
        # Spread drones evenly across the grid
        self.lat = LAT_MIN + (LAT_MAX - LAT_MIN) * (drone_id / 5)
        self.lng = LNG_MIN + (LNG_MAX - LNG_MIN) * 0.5
        self.altitude = 30.0 + drone_id * 5
        self.battery = 100
        self.angle = random.uniform(0, 2 * math.pi)

    def step(self):
        # Random walk within grid bounds
        self.angle += random.uniform(-0.5, 0.5)
        step = 0.002
        self.lat = max(LAT_MIN, min(LAT_MAX, self.lat + math.cos(self.angle) * step))
        self.lng = max(LNG_MIN, min(LNG_MAX, self.lng + math.sin(self.angle) * step))
        self.battery = max(10, self.battery - random.uniform(0.05, 0.15))

    def telemetry(self) -> dict:
        return {
            "lat": round(self.lat, 6),
            "lng": round(self.lng, 6),
            "altitude": round(self.altitude, 1),
            "battery": int(self.battery),
            "status": "active" if self.battery > 20 else "returning",
        }

    def rss(self) -> dict:
        # Simulate RSS weakening with distance from centre
        cx, cy = (LAT_MIN + LAT_MAX) / 2, (LNG_MIN + LNG_MAX) / 2
        dist = math.sqrt((self.lat - cx) ** 2 + (self.lng - cy) ** 2)
        rss_dbm = -40 - dist * 600 + random.uniform(-5, 5)
        return {"rss_dbm": round(max(-100, min(-40, rss_dbm)), 1)}


async def run(num_drones: int, trigger_detect: bool):
    drones = [DroneSim(i + 1) for i in range(num_drones)]

    async with httpx.AsyncClient(base_url=BASE_URL, timeout=3.0) as client:
        print(f"Simulating {num_drones} drone(s) — Ctrl+C to stop\n")

        if trigger_detect:
            await asyncio.sleep(1)
            await _send_detection(client, drones[0])

        tick = 0
        while True:
            for drone in drones:
                drone.step()

                # Telemetry every tick
                r = await client.post(f"/drones/{drone.drone_id}/telemetry", json=drone.telemetry())
                print(f"[{tick:>4}] drone {drone.drone_id}  "
                      f"lat={drone.lat:.4f} lng={drone.lng:.4f}  "
                      f"bat={int(drone.battery)}%  → {r.status_code}")

                # RSS signal every other tick
                if tick % 2 == 0:
                    signal = drone.rss()
                    r = await client.post(f"/drones/{drone.drone_id}/signal", json=signal)
                    print(f"       signal  rss={signal['rss_dbm']} dBm  → {r.status_code}")

            # Random detection every ~20 ticks
            if tick > 0 and tick % 20 == 0:
                await _send_detection(client, random.choice(drones))

            tick += 1
            await asyncio.sleep(1)


async def _send_detection(client: httpx.AsyncClient, drone: DroneSim):
    # Determine current cell_id from drone position
    row = int((drone.lat - LAT_MIN) / (LAT_MAX - LAT_MIN) * 10)
    col = int((drone.lng - LNG_MIN) / (LNG_MAX - LNG_MIN) * 10)
    cell_id = f"{chr(65 + min(row, 9))}{min(col, 9)}"

    payload = {
        "drone_id": drone.drone_id,
        "cell_id": cell_id,
        "rss_dbm": round(random.uniform(-55, -40), 1),
        "stream_url": None,
    }
    r = await client.post("/detection", json=payload)
    print(f"\n*** DETECTION SENT  drone={drone.drone_id} cell={cell_id}  → {r.status_code} ***\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--drones", type=int, default=3)
    parser.add_argument("--detect", action="store_true", help="Trigger a detection event on startup")
    parser.add_argument("--url", default=None, help="Server base URL (overrides DRONE_SERVER_URL env var)")
    args = parser.parse_args()

    if args.url:
        BASE_URL = args.url

    try:
        asyncio.run(run(args.drones, args.detect))
    except KeyboardInterrupt:
        print("\nStopped.")
