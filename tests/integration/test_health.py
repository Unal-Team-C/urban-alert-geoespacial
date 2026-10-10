from dataclasses import replace

import httpx

from app.config import get_settings
from app.main import create_app


async def test_health_ok(client: httpx.AsyncClient):
    response = await client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


async def test_health_unavailable_when_database_is_down():
    settings = replace(get_settings(), database_url="postgresql://nobody:nothing@127.0.0.1:1/none", db_pool_min=0)
    app = create_app(settings)
    async with app.router.lifespan_context(app):
        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
            response = await client.get("/health")
    assert response.status_code == 503
    assert response.json() == {"status": "unavailable"}
