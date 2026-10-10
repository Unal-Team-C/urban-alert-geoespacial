"""HTTP endpoints. Validation lives in the schemas; data access in app.db.repository."""

from typing import Annotated
from uuid import UUID

import asyncpg
from fastapi import APIRouter, Path, Query, Request, Response
from fastapi.responses import JSONResponse

from app.api.errors import ConflictError, CoordinateNotFoundError
from app.api.schemas import AssignLocation, Coordinate, ErrorResponse, LocationAssigned, NearbyQuery, NearbyReport
from app.db import repository
from app.db.repository import CoordinateRecord
from app.domain.geo import same_point

health_router = APIRouter()
router = APIRouter(prefix="/api/v1/geospatial")

ERRORS = {
    400: {"model": ErrorResponse, "description": "Invalid parameter"},
    503: {"model": ErrorResponse, "description": "Database unavailable"},
}


def get_pool(request: Request) -> asyncpg.Pool:
    return request.app.state.pool


def _location_assigned(record: CoordinateRecord) -> LocationAssigned:
    return LocationAssigned(
        coordinate_id=record.coordinate_id,
        report_id=record.report_id,
        coordinate=Coordinate(lat=record.lat, lon=record.lon),
    )


@health_router.get("/health", summary="Service health", tags=["health"])
async def health(request: Request) -> JSONResponse:
    if await repository.ping(get_pool(request)):
        return JSONResponse(status_code=200, content={"status": "ok"})
    return JSONResponse(status_code=503, content={"status": "unavailable"})


@router.post(
    "/coordinates",
    status_code=201,
    response_model=LocationAssigned,
    summary="Assign a location to a report (AssignLocation → LocationAssigned)",
    description=(
        "Called synchronously by the Reports service while creating a report. "
        "201 for a new assignment; 200 with the same coordinateId when the identical request is repeated; "
        "409 when the report already has a different location."
    ),
    responses={
        200: {"model": LocationAssigned, "description": "Repeated request: existing assignment"},
        409: {"model": ErrorResponse, "description": "Report already has a different location"},
        **ERRORS,
    },
    tags=["coordinates"],
)
async def assign_location(body: AssignLocation, request: Request, response: Response) -> LocationAssigned:
    lat, lon = body.coordinate.lat, body.coordinate.lon
    record, created = await repository.assign(get_pool(request), body.report_id, lat, lon)
    if created:
        response.headers["Location"] = f"{router.prefix}/coordinates/{record.coordinate_id}"
    elif same_point(record.lat, record.lon, lat, lon):
        response.status_code = 200
    else:
        raise ConflictError()
    return _location_assigned(record)


@router.get(
    "/coordinates/{coordinateId}",
    response_model=LocationAssigned,
    summary="Resolve a coordinate by its id",
    responses={404: {"model": ErrorResponse, "description": "Coordinate not found"}, **ERRORS},
    tags=["coordinates"],
)
async def get_coordinate(coordinate_id: Annotated[UUID, Path(alias="coordinateId")], request: Request) -> LocationAssigned:
    record = await repository.get_by_id(get_pool(request), coordinate_id)
    if record is None:
        raise CoordinateNotFoundError()
    return _location_assigned(record)


@router.get(
    "/reports",
    response_model=list[NearbyReport],
    summary="Reports near a point",
    description=(
        "Reports whose location is within `radius` meters (inclusive) of (`lat`, `lon`), nearest first. "
        "The point must be inside the Bogotá range and 0 < radius <= the configured maximum (6000 m by default). "
        "An area without reports returns an empty list."
    ),
    responses=ERRORS,
    tags=["reports"],
)
async def nearby_reports(query: Annotated[NearbyQuery, Query()], request: Request) -> Response:
    # Body already serialized by PostGIS in the NearbyReport shape (plan D-012); response_model documents it.
    body = await repository.find_nearby_json(get_pool(request), query.lat, query.lon, query.radius)
    return Response(content=body, media_type="application/json")
