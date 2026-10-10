"""Data access. Every statement is parameterized ($1, $2, ...); input is never interpolated into SQL."""

from dataclasses import dataclass
from uuid import UUID

import asyncpg

# Errors meaning "the database cannot be reached right now" (mapped to 503 by app.api.errors).
DB_UNAVAILABLE_ERRORS: tuple[type[Exception], ...] = (
    OSError,  # includes ConnectionRefusedError and TimeoutError
    asyncpg.InterfaceError,
    asyncpg.PostgresConnectionError,
    asyncpg.CannotConnectNowError,
    asyncpg.TooManyConnectionsError,
)

# ST_DWithin and ST_Distance use different geodesic algorithms that disagree by < 1 µm, which would
# drop a point lying exactly on the radius. 1 mm keeps the limit inclusive (plan D-011).
DISTANCE_TOLERANCE_M = 0.001

_INSERT = """
    INSERT INTO coordinates (report_id, location)
    VALUES ($1, ST_SetSRID(ST_MakePoint($3, $2), 4326)::geography)
    ON CONFLICT (report_id) DO NOTHING
    RETURNING coordinate_id, report_id, ST_Y(location::geometry) AS lat, ST_X(location::geometry) AS lon
"""

_SELECT_BY_REPORT = """
    SELECT coordinate_id, report_id, ST_Y(location::geometry) AS lat, ST_X(location::geometry) AS lon
    FROM coordinates
    WHERE report_id = $1
"""

_SELECT_BY_ID = """
    SELECT coordinate_id, report_id, ST_Y(location::geometry) AS lat, ST_X(location::geometry) AS lon
    FROM coordinates
    WHERE coordinate_id = $1
"""

# The JSON response body is built by PostGIS (plan D-012): one round trip, no per-report Python objects.
_SELECT_NEARBY_JSON = """
    SELECT COALESCE(
        json_agg(
            json_build_object(
                'reportId', report_id,
                'coordinateId', coordinate_id,
                'coordinate', json_build_object('lat', ST_Y(location::geometry), 'lon', ST_X(location::geometry))
            )
            ORDER BY location <-> ST_SetSRID(ST_MakePoint($2, $1), 4326)::geography
        ),
        '[]'::json
    )::text
    FROM coordinates
    WHERE ST_DWithin(location, ST_SetSRID(ST_MakePoint($2, $1), 4326)::geography, $3)
"""


@dataclass(frozen=True)
class CoordinateRecord:
    coordinate_id: UUID
    report_id: UUID
    lat: float
    lon: float


def _record(row: asyncpg.Record) -> CoordinateRecord:
    return CoordinateRecord(row["coordinate_id"], row["report_id"], row["lat"], row["lon"])


async def ping(pool: asyncpg.Pool) -> bool:
    try:
        async with pool.acquire() as connection:
            return await connection.fetchval("SELECT 1") == 1
    except DB_UNAVAILABLE_ERRORS:
        return False


async def assign(pool: asyncpg.Pool, report_id: UUID, lat: float, lon: float) -> tuple[CoordinateRecord, bool]:
    """Insert the report's location. Returns (record, created); created is False if the report already had one."""
    async with pool.acquire() as connection:
        row = await connection.fetchrow(_INSERT, report_id, lat, lon)
        if row is not None:
            return _record(row), True
        existing = await connection.fetchrow(_SELECT_BY_REPORT, report_id)
        return _record(existing), False


async def get_by_id(pool: asyncpg.Pool, coordinate_id: UUID) -> CoordinateRecord | None:
    async with pool.acquire() as connection:
        row = await connection.fetchrow(_SELECT_BY_ID, coordinate_id)
    return _record(row) if row is not None else None


async def find_nearby_json(pool: asyncpg.Pool, lat: float, lon: float, radius_m: float) -> str:
    """JSON array of the reports within radius_m meters (inclusive) of the point, nearest first."""
    async with pool.acquire() as connection:
        return await connection.fetchval(_SELECT_NEARBY_JSON, lat, lon, radius_m + DISTANCE_TOLERANCE_M)
