import unittest

from lora_serial import LoRaLineParser


class LoRaLineParserTests(unittest.TestCase):
    def test_parses_compact_firmware_line(self) -> None:
        reading = LoRaLineParser().feed("LORA_SAMPLE|-67|8|survivor-01")

        self.assertIsNotNone(reading)
        self.assertEqual(reading.payload, "survivor-01")
        self.assertEqual(reading.rss_dbm, -67)
        self.assertEqual(reading.snr_db, 8)

    def test_preserves_separator_inside_payload(self) -> None:
        reading = LoRaLineParser().feed("LORA_SAMPLE|-58|10|node|seq=3")

        self.assertEqual(reading.payload, "node|seq=3")

    def test_parses_legacy_multiline_log(self) -> None:
        parser = LoRaLineParser()

        self.assertIsNone(parser.feed("LORA RX DATA: survivor-01"))
        self.assertIsNone(parser.feed("RSSI: -72"))
        reading = parser.feed("SNR: 4")

        self.assertEqual(reading.payload, "survivor-01")
        self.assertEqual(reading.rss_dbm, -72)
        self.assertEqual(reading.snr_db, 4)

    def test_ignores_malformed_line(self) -> None:
        self.assertIsNone(LoRaLineParser().feed("LORA_SAMPLE|bad|3|node"))


if __name__ == "__main__":
    unittest.main()
