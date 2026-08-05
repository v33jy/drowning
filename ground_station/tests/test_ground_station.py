import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from main import parse_fpga_data


class ParseFpgaDataTests(unittest.TestCase):
    def test_valid_detected(self):
        result = parse_fpga_data("DET,1,13,08193")
        self.assertEqual(
            result,
            {"detected": True, "fft_bin": 13, "magnitude": 8193},
        )

    def test_valid_not_detected(self):
        result = parse_fpga_data("DET,0,13,00512")
        self.assertEqual(result["detected"], False)

    def test_wrong_prefix_returns_none(self):
        self.assertIsNone(parse_fpga_data("RSSI,1,13,08193"))

    def test_wrong_field_count_returns_none(self):
        self.assertIsNone(parse_fpga_data("DET,1,13"))

    def test_non_numeric_field_returns_none(self):
        self.assertIsNone(parse_fpga_data("DET,1,abc,08193"))

    def test_empty_string_returns_none(self):
        self.assertIsNone(parse_fpga_data(""))


if __name__ == "__main__":
    unittest.main()
