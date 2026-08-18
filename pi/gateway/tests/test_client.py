import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import requests

from client import GatewayClient, extract_drone_id


class ExtractDroneIdTests(unittest.TestCase):
    def test_extracts_integer_id(self):
        self.assertEqual(extract_drone_id("drone-01"), 1)

    def test_handles_no_prefix(self):
        self.assertEqual(extract_drone_id("7"), 7)


def _ok_response(payload: dict) -> MagicMock:
    response = MagicMock()
    response.status_code = 200
    response.raise_for_status.return_value = None
    response.json.return_value = payload
    return response


class PostWithRetryTests(unittest.TestCase):
    def setUp(self):
        self.client = GatewayClient(server_url="http://example.test", gateway_id="gw", max_retries=3, dry_run=False)

    def tearDown(self):
        self.client.close()

    @patch("client.time.sleep")
    def test_succeeds_first_try(self, mock_sleep):
        with patch.object(self.client.session, "post", return_value=_ok_response({"ok": True})) as mock_post:
            result = self.client._post_with_retry("/x", {"a": 1})

        self.assertEqual(result, {"ok": True})
        mock_post.assert_called_once()
        mock_sleep.assert_not_called()

    @patch("client.time.sleep")
    def test_retries_then_succeeds(self, mock_sleep):
        with patch.object(
            self.client.session, "post",
            side_effect=[requests.RequestException("boom"), _ok_response({"ok": True})],
        ) as mock_post:
            result = self.client._post_with_retry("/x", {"a": 1})

        self.assertEqual(result, {"ok": True})
        self.assertEqual(mock_post.call_count, 2)
        mock_sleep.assert_called_once()

    @patch("client.time.sleep")
    def test_gives_up_after_max_retries(self, mock_sleep):
        with patch.object(
            self.client.session, "post", side_effect=requests.RequestException("boom"),
        ) as mock_post:
            result = self.client._post_with_retry("/x", {"a": 1})

        self.assertIsNone(result)
        self.assertEqual(mock_post.call_count, self.client.max_retries)

    def test_dry_run_skips_network(self):
        dry_client = GatewayClient(server_url="http://example.test", gateway_id="gw", dry_run=True)
        try:
            with patch.object(dry_client.session, "post") as mock_post:
                result = dry_client._post_with_retry("/x", {"a": 1})
            self.assertEqual(result, {})
            mock_post.assert_not_called()
        finally:
            dry_client.close()


class SendTelemetryTests(unittest.TestCase):
    def setUp(self):
        self.client = GatewayClient(server_url="http://example.test", gateway_id="gw", dry_run=True)

    def tearDown(self):
        self.client.close()

    def test_missing_battery_posts_unknown_value(self):
        with patch.object(
            self.client,
            "_post_with_retry",
            return_value={"cell_id": "A0"},
        ) as mock_post:
            result = self.client.send_telemetry({
                "drone_id": "drone-01",
                "latitude": 1.0,
                "longitude": 2.0,
            })

        mock_post.assert_called_once_with("/drones/1/telemetry", {
            "lat": 1.0,
            "lng": 2.0,
            "altitude": 0.0,
            "battery": None,
            "status": "active",
        })
        self.assertEqual(result, {"cell_id": "A0"})

    def test_valid_payload_posts_to_telemetry_path(self):
        with patch.object(self.client, "_post_with_retry", return_value={"cell_id": "A0"}) as mock_post:
            result = self.client.send_telemetry({
                "drone_id": "drone-03", "latitude": 1.0, "longitude": 2.0, "battery": 90,
            })

        mock_post.assert_called_once_with("/drones/3/telemetry", {
            "lat": 1.0, "lng": 2.0, "altitude": 0.0, "battery": 90, "status": "active",
        })
        self.assertEqual(result, {"cell_id": "A0"})


class SendSignalTests(unittest.TestCase):
    def setUp(self):
        self.client = GatewayClient(server_url="http://example.test", gateway_id="gw", dry_run=True)

    def tearDown(self):
        self.client.close()

    @patch("client.uuid.uuid4", return_value="sample-1")
    def test_posts_sample_position_and_time(self, _mock_uuid):
        with patch.object(self.client, "_post_with_retry", return_value={"ok": True}) as mock_post:
            result = self.client.send_signal(
                3,
                -61.5,
                lat=37.5,
                lng=127.0,
                altitude=42.0,
                measured_at=1_700_000_000.0,
            )

        mock_post.assert_called_once_with("/drones/3/signal", {
            "measurement_id": "sample-1",
            "rss_dbm": -61.5,
            "lat": 37.5,
            "lng": 127.0,
            "altitude": 42.0,
            "measured_at": 1_700_000_000.0,
        })
        self.assertTrue(result)


if __name__ == "__main__":
    unittest.main()
