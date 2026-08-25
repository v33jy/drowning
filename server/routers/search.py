from __future__ import annotations

from fastapi import APIRouter, HTTPException

import state
from models import CandidateReview, CandidateRouteRequest, WsMessage
from route_planner import cell_center, optimize_route, route_length

router = APIRouter(prefix="/search", tags=["search"])


@router.put("/candidates/{cell_id}", summary="Record the visual review of a candidate cell")
async def review_candidate(cell_id: str, review: CandidateReview) -> dict:
    async with state.lock:
        try:
            state.heatmap.review_candidate(cell_id, review.outcome)
        except ValueError as error:
            raise HTTPException(status_code=409, detail=str(error)) from error
        snapshot = state.heatmap.snapshot()

    await state.manager.broadcast(WsMessage.heatmap_update(snapshot))
    return {"ok": True, "cell_id": cell_id, "outcome": review.outcome}


@router.post("/route", summary="Calculate a battery-efficient candidate visit order")
async def candidate_route(request: CandidateRouteRequest) -> dict:
    drone = state.drone_states.get(request.drone_id)
    if drone is None:
        raise HTTPException(status_code=404, detail="Unknown drone")
    candidates = [
        cell["cell_id"]
        for cell in state.heatmap.snapshot()
        if cell["status"] == "needs_recheck"
    ]
    start = (drone["lat"], drone["lng"])
    order = optimize_route(start, candidates)
    return {
        "drone_id": request.drone_id,
        "order": order,
        "distance_meters": round(route_length(start, order), 1),
        "waypoints": [
            {"cell_id": cell_id, "lat": cell_center(cell_id)[0], "lng": cell_center(cell_id)[1]}
            for cell_id in order
        ],
    }
