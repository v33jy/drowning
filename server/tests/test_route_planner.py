import unittest

import config
from route_planner import optimize_route, route_length


class RoutePlannerTests(unittest.TestCase):
    def test_visits_near_candidate_before_far_candidate(self):
        route = optimize_route(
            (config.LAT_MIN + 0.0001, config.LNG_MIN + 0.0001),
            ["A3", "A0"],
        )
        self.assertEqual(route, ["A0", "A3"])

    def test_route_contains_each_candidate_once(self):
        candidates = ["A0", "C3", "B1", "D4"]
        start = (config.LAT_MIN, config.LNG_MIN)
        route = optimize_route(start, candidates)
        self.assertCountEqual(route, candidates)
        self.assertEqual(len(route), len(set(route)))
        self.assertGreater(route_length(start, route), 0)


if __name__ == "__main__":
    unittest.main()
