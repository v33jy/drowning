"""Small, deterministic route optimizer for candidate-cell revisits."""

from __future__ import annotations

import math

import config
from heatmap import cell_bounds


def cell_center(cell_id: str) -> tuple[float, float]:
    row = ord(cell_id[0]) - 65
    col = int(cell_id[1:])
    bounds = cell_bounds(row, col)
    return (
        (bounds["lat_min"] + bounds["lat_max"]) / 2,
        (bounds["lng_min"] + bounds["lng_max"]) / 2,
    )


def distance_meters(a: tuple[float, float], b: tuple[float, float]) -> float:
    lat_scale = 111_320
    mean_lat = math.radians((a[0] + b[0]) / 2)
    north = (a[0] - b[0]) * lat_scale
    east = (a[1] - b[1]) * lat_scale * math.cos(mean_lat)
    return math.hypot(north, east)


def route_length(start: tuple[float, float], route: list[str]) -> float:
    total = 0.0
    current = start
    for cell_id in route:
        target = cell_center(cell_id)
        total += distance_meters(current, target)
        current = target
    return total


def optimize_route(start: tuple[float, float], candidate_ids: list[str]) -> list[str]:
    """Nearest-neighbour seed followed by 2-opt improvement."""
    remaining = set(candidate_ids)
    route: list[str] = []
    current = start
    while remaining:
        next_id = min(
            remaining,
            key=lambda cell_id: (
                distance_meters(current, cell_center(cell_id)),
                -config.grid_priority(cell_id),
                cell_id,
            ),
        )
        route.append(next_id)
        remaining.remove(next_id)
        current = cell_center(next_id)

    improved = True
    while improved:
        improved = False
        baseline = route_length(start, route)
        for left in range(len(route) - 1):
            for right in range(left + 1, len(route)):
                candidate = route[:left] + list(reversed(route[left:right + 1])) + route[right + 1:]
                if route_length(start, candidate) + 0.01 < baseline:
                    route = candidate
                    improved = True
                    break
            if improved:
                break
    return route
