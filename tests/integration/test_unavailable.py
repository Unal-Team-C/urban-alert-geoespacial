from collections.abc import AsyncIterator
from dataclasses import replace
from uuid import uuid4

import httpx
import pytest

from app.config import get_settings
from app.main import create_app

UNAVAILABLE = {"code": 503, "message": "Service unavailable"}


@pytest.fixture
async def down_client() -> AsyncIterator[httpx.AsyncClient]:
    """Client for an app whose database is unreachable (closed port)."""
    settings = replace(get_settings(), database_url="postgresql://nobody:nothing@127.0.0.1:1/none", db_pool_min=0)
    app = create_app(settings)
    async with app.router.lifespan_context(app):
        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
            yield client


async def test_assign_returns_503(down_client: httpx.AsyncClient):
    response = await down_client.post(
        "/api/v1/geospatial/coordinates",
        json={"reportId": str(uuid4()), "coordinate": {"lat": 4.6512, "lon": -74.0561}},
    )
    assert response.status_code == 503
    assert response.json() == UNAVAILABLE


async def test_get_coordinate_returns_503(down_client: httpx.AsyncClient):
    response = await down_client.get(f"/api/v1/geospatial/coordinates/{uuid4()}")
    assert response.status_code == 503
    assert response.json() == UNAVAILABLE


async def test_nearby_returns_503(down_client: httpx.AsyncClient):
    response = await down_client.get("/api/v1/geospatial/reports", params={"lat": 4.65, "lon": -74.06, "radius": 500})
    assert response.status_code == 503
    assert response.json() == UNAVAILABLE


async def test_invalid_input_is_still_400_when_database_is_down(down_client: httpx.AsyncClient):
    response = await down_client.get("/api/v1/geospatial/reports", params={"lat": 4.65, "lon": -74.06, "radius": 6001})
    assert response.status_code == 400
