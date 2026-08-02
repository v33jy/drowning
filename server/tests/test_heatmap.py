import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import config
from heatmap import HeatmapState, grid_definition, latlng_to_cell_id, rss_to_color


class RssToColorTests(unittest.TestCase):
    def test_min_rss_is_blue(self):
        self.assertEqual(rss_to_color(config.RSS_MIN), "#0000FF")

    def test_max_rss_is_red(self):
        self.assertEqual(rss_to_color(config.RSS_MAX), "#FF0000")

    def test_clamps_below_min(self):
        self.assertEqual(rss_to_color(config.RSS_MIN - 20), rss_to_color(config.RSS_MIN))

    def test_clamps_above_max(self):
        self.assertEqual(rss_to_color(config.RSS_MAX + 20), rss_to_color(config.RSS_MAX))

    def test_returns_hex_format(self):
        self.assertRegex(rss_to_color(-70.0), r"^#[0-9A-F]{6}$")


class LatLngToCellIdTests(unittest.TestCase):
    def test_inside_grid_returns_cell_id(self):
        mid_lat = (config.LAT_MIN + config.LAT_MAX) / 2
        mid_lng = (config.LNG_MIN + config.LNG_MAX) / 2
        self.assertIsNotNone(latlng_to_cell_id(mid_lat, mid_lng))

    def test_outside_grid_returns_none(self):
        self.assertIsNone(latlng_to_cell_id(config.LAT_MIN - 1, config.LNG_MIN))
        self.assertIsNone(latlng_to_cell_id(config.LAT_MIN, config.LNG_MAX + 1))

    def test_top_right_corner_clamps_into_last_cell(self):
        # Exactly at LAT_MAX/LNG_MAX would fall one row/col past the grid without clamping.
        cell_id = latlng_to_cell_id(config.LAT_MAX, config.LNG_MAX)
        self.assertEqual(cell_id, f"{chr(65 + config.GRID_ROWS - 1)}{config.GRID_COLS - 1}")


class GridDefinitionTests(unittest.TestCase):
    def test_cell_count_matches_grid_size(self):
        cells = grid_definition()
        self.assertEqual(len(cells), config.GRID_ROWS * config.GRID_COLS)


class HeatmapStateTests(unittest.TestCase):
    def setUp(self):
        self.heatmap = HeatmapState()

    def test_initial_snapshot_is_all_unscanned(self):
        snapshot = self.heatmap.snapshot()
        self.assertEqual(len(snapshot), config.GRID_ROWS * config.GRID_COLS)
        self.assertTrue(all(cell["status"] == "unscanned" for cell in snapshot))

    def test_update_unknown_cell_raises(self):
        with self.assertRaises(ValueError):
            self.heatmap.update("Z99", drone_id=1, rss_dbm=-60.0)

    def test_update_marks_cell_active(self):
        self.heatmap.update("A0", drone_id=1, rss_dbm=-60.0)
        cell = next(c for c in self.heatmap.snapshot() if c["cell_id"] == "A0")
        self.assertEqual(cell["status"], "active")
        self.assertEqual(cell["drone_id"], 1)
        self.assertEqual(cell["rss_dbm"], -60.0)


if __name__ == "__main__":
    unittest.main()
