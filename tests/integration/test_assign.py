import asyncio
from uuid import UUID, uuid4

import httpx
from fastapi import FastAPI

URL = "/api/v1/geospatial/coordinates"
CHAPINERO = {"lat": 4.6512, "lon": -74.0561}


async def count_rows(app: FastAPI) -> int:
    async with app.state.pool.acquire() as connection:
        return await connection.fetchval("SELECT count(*) FROM coordinates")


async def test_new_assignment_returns_201(client: httpx.AsyncClient, app: FastAPI):
    report_id = str(uuid4())
    response = await client.post(URL, json={"reportId": report_id, "coordinate": CHAPINERO})

    assert response.status_code == 201
    body = response.json()
    assert set(body) == {"coordinateId", "reportId", "coordinate"}
    assert body["reportId"] == report_id
    assert body["coordinate"] == CHAPINERO
    UUID(body["coordinateId"])
    assert response.headers["Location"] == f"{URL}/{body['coordinateId']}"
    assert await count_rows(app) == 1


async def test_repeated_identical_request_returns_200_with_same_id(client: httpx.AsyncClient, app: FastAPI):
    payload = {"reportId": str(uuid4()), "coordinate": CHAPINERO}
    first = await client.post(URL, json=payload)
    second = await client.post(URL, json=payload)

    assert (first.status_code, second.status_code) == (201, 200)
    assert second.json() == first.json()
    assert await count_rows(app) == 1


async def test_same_report_with_different_coordinate_returns_409(client: httpx.AsyncClient, app: FastAPI):
    report_id = str(uuid4())
    first = await client.post(URL, json={"reportId": report_id, "coordinate": CHAPINERO})
    second = await client.post(URL, json={"reportId": report_id, "coordinate": {"lat": 4.7, "lon": -74.05}})

    assert second.status_code == 409
    assert second.json() == {"code": 409, "message": "Report already has a different location"}
    async with app.state.pool.acquire() as connection:
        stored = await connection.fetchrow("SELECT ST_Y(location::geometry) AS lat, ST_X(location::geometry) AS lon FROM coordinates")
    assert dict(stored) == CHAPINERO
    assert first.status_code == 201
    assert await count_rows(app) == 1


async def test_concurrent_identical_requests_create_one_row(client: httpx.AsyncClient, app: FastAPI):
    payload = {"reportId": str(uuid4()), "coordinate": CHAPINERO}
    responses = await asyncio.gather(*(client.post(URL, json=payload) for _ in range(10)))

    statuses = sorted(r.status_code for r in responses)
    assert statuses == [200] * 9 + [201]
    assert len({r.json()["coordinateId"] for r in responses}) == 1
    assert await count_rows(app) == 1


async def test_coordinate_outside_bogota_returns_400_and_stores_nothing(client: httpx.AsyncClient, app: FastAPI):
    response = await client.post(URL, json={"reportId": str(uuid4()), "coordinate": {"lat": 6.2442, "lon": -75.5812}})

    assert response.status_code == 400
    assert response.json()["message"] == "Invalid parameter"
    assert await count_rows(app) == 0


async def test_invalid_report_id_returns_400(client: httpx.AsyncClient, app: FastAPI):
    response = await client.post(URL, json={"reportId": "not-a-uuid", "coordinate": CHAPINERO})

    assert response.status_code == 400
    assert response.json()["details"][0]["field"] == "reportId"
    assert await count_rows(app) == 0
