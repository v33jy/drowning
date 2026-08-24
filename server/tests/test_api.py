import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import config
import state
from heatmap import HeatmapState
from main import app
from starlette.testclient import TestClient


class ApiTestCase(unittest.TestCase):
    """Base class: resets the module-global in-memory state before each test.

    server/state.py is a single process-global store (see its docstring) —
    without this reset, tests would leak drone/detection data into each other.
    """

    def setUp(self):
        state.drone_states.clear()
        state.detections.clear()
        state.signal_readings.clear()
        state.signal_readings_by_id.clear()
        state.heatmap = HeatmapState()
        state.manager._clients.clear()
        state.call_sessions.clear()
        state.survivor_waiting.clear()
        self.client = TestClient(app)

    def _mid_point(self):
        return {
            "lat": (config.LAT_MIN + config.LAT_MAX) / 2,
            "lng": (config.LNG_MIN + config.LNG_MAX) / 2,
        }


class TelemetryTests(ApiTestCase):
    def test_post_telemetry_then_list_drones(self):
        payload = {**self._mid_point(), "altitude": 50.0, "battery": 80}
        resp = self.client.post("/drones/1/telemetry", json=payload)
        self.assertEqual(resp.status_code, 200)
        self.assertIsNotNone(resp.json()["cell_id"])

        listed = self.client.get("/drones").json()
        self.assertEqual(len(listed), 1)
        self.assertEqual(listed[0]["drone_id"], 1)

    def test_post_telemetry_accepts_unknown_battery(self):
        payload = {
            **self._mid_point(),
            "altitude": 50.0,
            "battery": None,
        }

        resp = self.client.post("/drones/1/telemetry", json=payload)

        self.assertEqual(resp.status_code, 200)
        self.assertIsNone(resp.json()["battery"])

        listed = self.client.get("/drones").json()
        self.assertIsNone(listed[0]["battery"])


class SignalTests(ApiTestCase):
    def test_signal_before_telemetry_returns_404(self):
        resp = self.client.post("/drones/1/signal", json={"rss_dbm": -60.0})
        self.assertEqual(resp.status_code, 404)

    def test_signal_after_telemetry_returns_cell_id(self):
        payload = {**self._mid_point(), "altitude": 50.0, "battery": 80}
        self.client.post("/drones/1/telemetry", json=payload)

        resp = self.client.post("/drones/1/signal", json={"rss_dbm": -60.0})
        self.assertEqual(resp.status_code, 200)
        self.assertTrue(resp.json()["ok"])
        self.assertIsNotNone(resp.json()["cell_id"])
        self.assertIn("measurement_id", resp.json())

        stored = state.signal_readings[-1]
        self.assertEqual(stored["rss_dbm"], -60.0)
        self.assertEqual(stored["lat"], payload["lat"])
        self.assertEqual(stored["lng"], payload["lng"])
        self.assertEqual(stored["altitude"], payload["altitude"])
        self.assertIsNotNone(stored["measured_at"])

    def test_signal_uses_measurement_coordinates_instead_of_latest_telemetry(self):
        telemetry = {**self._mid_point(), "altitude": 50.0, "battery": 80}
        self.client.post("/drones/1/telemetry", json=telemetry)
        measured_at = 1_700_000_000.0
        sample = {
            "rss_dbm": -55.0,
            "lat": config.LAT_MIN,
            "lng": config.LNG_MIN,
            "altitude": 25.0,
            "measured_at": measured_at,
        }

        resp = self.client.post("/drones/1/signal", json=sample)

        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.json()["cell_id"], "A0")
        stored = state.signal_readings[-1]
        self.assertEqual(stored["cell_id"], "A0")
        self.assertEqual(stored["measured_at"], measured_at)
        self.assertEqual(stored["altitude"], 25.0)

    def test_signal_with_coordinates_does_not_require_prior_telemetry(self):
        resp = self.client.post("/drones/1/signal", json={
            "rss_dbm": -60.0,
            **self._mid_point(),
            "measured_at": 1_700_000_000.0,
        })

        self.assertEqual(resp.status_code, 200)
        self.assertEqual(len(state.signal_readings), 1)

    def test_signal_rejects_partial_coordinates(self):
        resp = self.client.post("/drones/1/signal", json={
            "rss_dbm": -60.0,
            "lat": self._mid_point()["lat"],
        })
        self.assertEqual(resp.status_code, 422)

    def test_retried_measurement_is_stored_only_once(self):
        sample = {
            "measurement_id": "sample-1",
            "rss_dbm": -60.0,
            **self._mid_point(),
            "measured_at": 1_700_000_000.0,
        }

        first = self.client.post("/drones/1/signal", json=sample)
        retried = self.client.post("/drones/1/signal", json=sample)

        self.assertEqual(first.status_code, 200)
        self.assertEqual(retried.status_code, 200)
        self.assertEqual(first.json(), retried.json())
        self.assertEqual(len(state.signal_readings), 1)

    def test_repeated_strong_signals_mark_cell_for_recheck(self):
        cell_id = None
        for index in range(config.SEARCH_RECHECK_MIN_SAMPLES):
            response = self.client.post(
                "/drones/1/signal",
                json={
                    "measurement_id": f"strong-{index}",
                    "rss_dbm": config.SEARCH_RECHECK_RSS_DBM,
                    **self._mid_point(),
                    "measured_at": 1_700_000_000.0 + index,
                },
            )
            self.assertEqual(response.status_code, 200)
            cell_id = response.json()["cell_id"]

        cell = next(
            item for item in state.heatmap.snapshot()
            if item["cell_id"] == cell_id
        )
        self.assertEqual(cell["status"], "needs_recheck")
        self.assertEqual(
            cell["strong_signal_count"],
            config.SEARCH_RECHECK_MIN_SAMPLES,
        )

    def test_signal_outside_grid_returns_422(self):
        payload = {"lat": config.LAT_MIN - 1, "lng": config.LNG_MIN - 1, "altitude": 50.0, "battery": 80}
        self.client.post("/drones/1/telemetry", json=payload)

        resp = self.client.post("/drones/1/signal", json={"rss_dbm": -60.0})
        self.assertEqual(resp.status_code, 422)


class DetectionTests(ApiTestCase):
    def test_report_then_list_detection(self):
        event = {"drone_id": 1, "cell_id": "A0", "rss_dbm": -55.0}
        resp = self.client.post("/detection", json=event)
        self.assertEqual(resp.status_code, 200)
        self.assertTrue(resp.json()["ok"])
        self.assertIn("detection_id", resp.json())

        listed = self.client.get("/detection").json()
        self.assertEqual(len(listed), 1)
        self.assertEqual(listed[0]["cell_id"], "A0")
        self.assertIn("call_session_id", listed[0])
        self.assertIn(listed[0]["call_session_id"], state.call_sessions)

    def test_default_stream_url_uses_api_request_host(self):
        event = {"drone_id": 1, "cell_id": "A0", "rss_dbm": -55.0}
        response = self.client.post(
            "/detection",
            json=event,
            headers={"host": "192.168.0.20:8001"},
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            state.detections[-1]["stream_url"],
            f"http://192.168.0.20:{config.MEDIAMTX_WHEP_PORT}/drone/whep",
        )

    def test_detection_stream_url_takes_precedence(self):
        stream_url = "http://media.local:8889/custom/whep"
        event = {
            "drone_id": 1,
            "cell_id": "A0",
            "rss_dbm": -55.0,
            "stream_url": stream_url,
        }
        response = self.client.post("/detection", json=event)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(state.detections[-1]["stream_url"], stream_url)


class MetaTests(ApiTestCase):
    def test_health(self):
        resp = self.client.get("/health")
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.json(), {"status": "ok"})

    def test_state_snapshot_shape(self):
        resp = self.client.get("/state")
        self.assertEqual(resp.status_code, 200)
        body = resp.json()
        self.assertIn("drones", body)
        self.assertIn("heatmap", body)
        self.assertIn("signal_readings", body)
        self.assertIn("detections", body)

    def test_heatmap_grid_cell_count(self):
        resp = self.client.get("/heatmap/grid")
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(len(resp.json()), config.GRID_ROWS * config.GRID_COLS)


class ControlWebSocketTests(ApiTestCase):
    def test_connect_receives_init_snapshot(self):
        with self.client.websocket_connect("/ws/control") as ws:
            message = ws.receive_json()
            self.assertEqual(message["type"], "init")
            self.assertEqual(message["data"]["drones"], [])

    def test_telemetry_broadcasts_drone_update(self):
        with self.client.websocket_connect("/ws/control") as ws:
            ws.receive_json()  # init

            payload = {**self._mid_point(), "altitude": 50.0, "battery": 80}
            self.client.post("/drones/1/telemetry", json=payload)

            message = ws.receive_json()
            self.assertEqual(message["type"], "drone_update")
            self.assertEqual(message["data"]["drone_id"], 1)


class CallWebSocketTests(ApiTestCase):
    def _session(self):
        session = state.CallSession(
            session_id="call-1",
            drone_id=1,
            cell_id="A0",
            created_at=0,
        )
        state.call_sessions[session.session_id] = session
        return session

    def test_rejects_unknown_session(self):
        with self.assertRaises(Exception):
            with self.client.websocket_connect("/calls/missing/control"):
                pass

    def test_control_call_notifies_waiting_survivor(self):
        event = {"drone_id": 1, "cell_id": "A0", "rss_dbm": -55.0}

        with self.client.websocket_connect("/survivors/listen") as survivor_ws:
            response = self.client.post("/detection", json=event)
            session_id = state.detections[-1]["call_session_id"]
            with self.client.websocket_connect(
                f"/calls/{session_id}/control"
            ):
                message = survivor_ws.receive_json()

        self.assertEqual(message["type"], "incoming_call")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(message["session_id"], session_id)
        self.assertIn(session_id, state.call_sessions)

    def test_late_survivor_listener_receives_pending_control_call(self):
        self._session()

        with self.client.websocket_connect("/calls/call-1/control"):
            with self.client.websocket_connect("/survivors/listen") as survivor_ws:
                self.assertEqual(
                    survivor_ws.receive_json(),
                    {"type": "incoming_call", "session_id": "call-1"},
                )

    def test_relays_signaling_message_unchanged(self):
        self._session()
        offer = {"type": "offer", "sdp": "test-sdp", "extra": {"value": 1}}

        with self.client.websocket_connect("/calls/call-1/control") as control_ws:
            with self.client.websocket_connect("/calls/call-1/survivor") as survivor_ws:
                self.assertEqual(control_ws.receive_json(), {"type": "peer-ready"})
                control_ws.send_json(offer)
                self.assertEqual(survivor_ws.receive_json(), offer)

    def test_call_end_deactivates_session(self):
        session = self._session()

        with self.client.websocket_connect("/calls/call-1/control") as control_ws:
            with self.client.websocket_connect("/calls/call-1/survivor") as survivor_ws:
                self.assertEqual(control_ws.receive_json(), {"type": "peer-ready"})
                control_ws.send_json({"type": "call-end"})
                self.assertEqual(survivor_ws.receive_json(), {"type": "call-end"})

        self.assertFalse(session.active)

    def test_unexpected_disconnect_notifies_remaining_peer(self):
        self._session()

        with self.client.websocket_connect("/calls/call-1/control") as control_ws:
            with self.client.websocket_connect("/calls/call-1/survivor") as survivor_ws:
                self.assertEqual(control_ws.receive_json(), {"type": "peer-ready"})

            self.assertEqual(
                control_ws.receive_json(),
                {"type": "peer-disconnected"},
            )


if __name__ == "__main__":
    unittest.main()
