import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from packet_parser import PacketParseError, parse_packet


class ParsePacketTests(unittest.TestCase):
    def test_valid_packet(self):
        result = parse_packet("drone-01,-65,37.5012,127.0324,87")
        self.assertEqual(result["drone_id"], "drone-01")
        self.assertEqual(result["rssi"], -65)
        self.assertEqual(result["latitude"], 37.5012)
        self.assertEqual(result["longitude"], 127.0324)
        self.assertEqual(result["battery"], 87)
        self.assertIn("received_at", result)

    def test_strips_whitespace(self):
        result = parse_packet("  drone-01,-65,37.5012,127.0324,87  \n")
        self.assertEqual(result["drone_id"], "drone-01")

    def test_empty_packet_raises(self):
        with self.assertRaises(PacketParseError):
            parse_packet("")

    def test_wrong_field_count_raises(self):
        with self.assertRaises(PacketParseError):
            parse_packet("drone-01,-65,37.5012,127.0324")

    def test_empty_drone_id_raises(self):
        with self.assertRaises(PacketParseError):
            parse_packet(",-65,37.5012,127.0324,87")

    def test_non_numeric_field_raises(self):
        with self.assertRaises(PacketParseError):
            parse_packet("drone-01,abc,37.5012,127.0324,87")

    def test_latitude_out_of_range_raises(self):
        with self.assertRaises(PacketParseError):
            parse_packet("drone-01,-65,95.0,127.0324,87")

    def test_longitude_out_of_range_raises(self):
        with self.assertRaises(PacketParseError):
            parse_packet("drone-01,-65,37.5012,200.0,87")

    def test_battery_out_of_range_raises(self):
        with self.assertRaises(PacketParseError):
            parse_packet("drone-01,-65,37.5012,127.0324,150")

    def test_rssi_out_of_range_raises(self):
        with self.assertRaises(PacketParseError):
            parse_packet("drone-01,10,37.5012,127.0324,87")


if __name__ == "__main__":
    unittest.main()
