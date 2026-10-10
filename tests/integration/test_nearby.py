from uuid import uuid4

import httpx
import pytest
from fastapi import FastAPI

REPORTS_URL = "/api/v1/geospatial/reports"
ASSIGN_URL = "/api/v1/geospatial/coordinates"
CENTER = (4.6486, -74.0628)  # Chapinero


async def point_at(app: FastAPI, origin: tuple[float, float], distance_m: float, azimuth_deg: float) -> tuple[float, float]:
    """Geodesic projection: the point at distance_m meters from origin along azimuth_deg."""
    async with app.state.pool.acquire() as connection:
        row = await connection.fetchrow(
            """
            SELECT ST_Y(p::geometry) AS lat, ST_X(p::geometry) AS lon
            FROM (SELECT ST_Project(ST_SetSRID(ST_MakePoint($2, $1), 4326)::geography, $3::float8, radians($4::float8)) AS p) AS t
            """,
            origin[0], origin[1], distance_m, azimuth_deg,
        )
    return row["lat"], row["lon"]


async def distance_m(app: FastAPI, a: tuple[float, float], b: tuple[float, float]) -> float:
    async with app.state.pool.acquire() as connection:
        return await connection.fetchval(
            """
            SELECT ST_Distance(ST_SetSRID(ST_MakePoint($2, $1), 4326)::geography,
                               ST_SetSRID(ST_MakePoint($4, $3), 4326)::geography)
            """,
            a[0], a[1], b[0], b[1],
        )


async def assign(client: httpx.AsyncClient, point: tuple[float, float]) -> dict:
    response = await client.post(
        ASSIGN_URL, json={"reportId": str(uuid4()), "coordinate": {"lat": point[0], "lon": point[1]}}
    )
    assert response.status_code == 201
    return response.json()


async def nearby(client: httpx.AsyncClient, point: tuple[float, float], radius: float) -> httpx.Response:
    return await client.get(REPORTS_URL, params={"lat": point[0], "lon": point[1], "radius": radius})


def report_ids(response: httpx.Response) -> list[str]:
    assert response.status_code == 200
    return [item["reportId"] for item in response.json()]


async def test_only_reports_within_radius_are_returned(client: httpx.AsyncClient, app: FastAPI):
    near = await assign(client, await point_at(app, CENTER, 300, 45))
    await assign(client, await point_at(app, CENTER, 800, 200))

    assert report_ids(await nearby(client, CENTER, 500)) == [near["reportId"]]


async def test_report_exactly_at_radius_is_included(client: httpx.AsyncClient, app: FastAPI):
    point = await point_at(app, CENTER, 500, 90)
    created = await assign(client, point)

    assert abs(await distance_m(app, CENTER, point) - 500) < 1e-6
    assert report_ids(await nearby(client, CENTER, 500)) == [created["reportId"]]
    assert report_ids(await nearby(client, CENTER, 499.99)) == []


async def test_area_without_reports_returns_empty_list(client: httpx.AsyncClient, app: FastAPI):
    await assign(client, await point_at(app, CENTER, 5000, 0))

    response = await nearby(client, CENTER, 1000)

    assert response.status_code == 200
    assert response.json() == []


async def test_new_point_or_radius_returns_only_the_new_area(client: httpx.AsyncClient, app: FastAPI):
    other_center = await point_at(app, CENTER, 3000, 0)
    in_first = await assign(client, await point_at(app, CENTER, 100, 0))
    in_second = await assign(client, await point_at(app, other_center, 100, 180))

    assert report_ids(await nearby(client, CENTER, 500)) == [in_first["reportId"]]
    assert report_ids(await nearby(client, other_center, 500)) == [in_second["reportId"]]
    assert report_ids(await nearby(client, CENTER, 4000)) == [in_first["reportId"], in_second["reportId"]]


async def test_results_are_ordered_nearest_first(client: httpx.AsyncClient, app: FastAPI):
    far = await assign(client, await point_at(app, CENTER, 900, 10))
    close = await assign(client, await point_at(app, CENTER, 100, 250))
    middle = await assign(client, await point_at(app, CENTER, 400, 130))

    assert report_ids(await nearby(client, CENTER, 1000)) == [close["reportId"], middle["reportId"], far["reportId"]]


async def test_max_radius_boundary(client: httpx.AsyncClient):
    assert (await nearby(client, CENTER, 6000)).status_code == 200

    response = await nearby(client, CENTER, 6001)
    assert response.status_code == 400
    assert response.json()["message"] == "Invalid parameter"


async def test_response_has_only_contract_fields(client: httpx.AsyncClient, app: FastAPI):
    point = await point_at(app, CENTER, 50, 0)
    created = await assign(client, point)

    response = await nearby(client, CENTER, 100)

    assert response.json() == [
        {
            "reportId": created["reportId"],
            "coordinateId": created["coordinateId"],
            "coordinate": {"lat": point[0], "lon": point[1]},
        }
    ]


async def test_point_outside_bogota_returns_400(client: httpx.AsyncClient):
    response = await nearby(client, (6.2442, -75.5812), 500)

    assert response.status_code == 400


async def test_missing_or_malformed_parameters_return_400(client: httpx.AsyncClient):
    assert (await client.get(REPORTS_URL, params={"lat": 4.65, "lon": -74.06})).status_code == 400
    assert (await client.get(REPORTS_URL, params={"lat": "' OR 1=1 --", "lon": -74.06, "radius": 500})).status_code == 400


@pytest.mark.parametrize("edge", [(4.84, -74.05), (4.60, -74.46)], ids=["north-edge", "west-edge"])
async def test_point_on_bogota_edge_with_radius_beyond_range(client: httpx.AsyncClient, app: FastAPI, edge):
    """The circle may extend outside Bogotá: only existing reports inside it are returned, without error."""
    inside = await assign(client, await point_at(app, edge, 1000, 135 if edge[0] == 4.84 else 90))

    response = await nearby(client, edge, 6000)

    assert report_ids(response) == [inside["reportId"]]
