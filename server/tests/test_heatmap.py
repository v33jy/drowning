import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import config
from heatmap import HeatmapState, grid_definition, latlng_to_cell_id


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

    def test_update_marks_cell_as_scanning(self):
        self.heatmap.update("A0", drone_id=1, rss_dbm=-60.0)
        cell = next(c for c in self.heatmap.snapshot() if c["cell_id"] == "A0")
        self.assertEqual(cell["status"], "scanning")
        self.assertEqual(cell["drone_id"], 1)
        self.assertEqual(cell["rss_dbm"], -60.0)
        self.assertEqual(cell["sample_count"], 1)
        self.assertEqual(cell["drone_count"], 1)

    def test_repeated_strong_signal_marks_cell_for_recheck(self):
        for drone_id in (1, 1, 2):
            self.heatmap.update(
                "A0",
                drone_id=drone_id,
                rss_dbm=config.SEARCH_RECHECK_RSS_DBM,
            )

        cell = next(c for c in self.heatmap.snapshot() if c["cell_id"] == "A0")
        self.assertEqual(cell["status"], "needs_recheck")
        self.assertEqual(cell["status_reason"], "repeated_strong_signal")
        self.assertEqual(cell["strong_signal_count"], 3)
        self.assertEqual(cell["drone_count"], 2)

    def test_summary_uses_recent_median_as_representative_rss(self):
        for rss_dbm in (-90.0, -60.0, -50.0):
            self.heatmap.update("A0", drone_id=1, rss_dbm=rss_dbm)

        cell = next(c for c in self.heatmap.snapshot() if c["cell_id"] == "A0")
        self.assertEqual(cell["rss_dbm"], -60.0)
        self.assertEqual(cell["average_rss_dbm"], -66.7)
        self.assertEqual(cell["peak_rss_dbm"], -50.0)

    def test_measurement_timestamp_is_preserved(self):
        self.heatmap.update(
            "A0", drone_id=1, rss_dbm=-70.0, measured_at=1_700_000_000.0
        )
        cell = next(c for c in self.heatmap.snapshot() if c["cell_id"] == "A0")
        self.assertEqual(cell["last_updated"], 1_700_000_000.0)

    def test_older_sample_does_not_replace_latest_sample_metadata(self):
        self.heatmap.update(
            "A0", drone_id=2, rss_dbm=-55.0, measured_at=200.0
        )
        self.heatmap.update(
            "A0", drone_id=1, rss_dbm=-80.0, measured_at=100.0
        )

        cell = next(c for c in self.heatmap.snapshot() if c["cell_id"] == "A0")
        self.assertEqual(cell["latest_rss_dbm"], -55.0)
        self.assertEqual(cell["drone_id"], 2)
        self.assertEqual(cell["last_updated"], 200.0)


if __name__ == "__main__":
    unittest.main()
