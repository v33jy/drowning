import unittest

from measurement import SignalMeasurement, SignalObservation


class SignalMeasurementTests(unittest.TestCase):
    def test_preserves_fractional_rss(self) -> None:
        measurement = SignalMeasurement(
            rss_dbm=-65.25,
            measured_at=123.0,
        )

        self.assertEqual(measurement.rss_dbm, -65.25)

    def test_rejects_positive_rss(self) -> None:
        with self.assertRaises(ValueError):
            SignalMeasurement(rss_dbm=1.0, measured_at=123.0)


class SignalObservationTests(unittest.TestCase):
    def test_builds_server_telemetry_payload(self) -> None:
        observation = SignalObservation(
            drone_id="drone-01",
            rss_dbm=-65.25,
            latitude=37.5012,
            longitude=127.0324,
            altitude=12.3,
            battery=87,
            signal_measured_at=124.0,
            position_measured_at=123.0,
        )

        self.assertEqual(
            observation.telemetry_payload(),
            {
                "drone_id": "drone-01",
                "latitude": 37.5012,
                "longitude": 127.0324,
                "altitude": 12.3,
                "battery": 87,
                "status": "active",
            },
        )


if __name__ == "__main__":
    unittest.main()
