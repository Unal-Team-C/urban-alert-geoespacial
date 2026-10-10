"""Shared fixtures. Integration tests use DATABASE_URL (geospatial_test in the compose 'tests' service)."""

from collections.abc import AsyncIterator

import httpx
import pytest
from fastapi import FastAPI

from app.main import create_app


@pytest.fixture(scope="session")
async def app() -> AsyncIterator[FastAPI]:
    application = create_app()
    async with application.router.lifespan_context(application):
        yield application


@pytest.fixture(scope="session")
async def client(app: FastAPI) -> AsyncIterator[httpx.AsyncClient]:
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as c:
        yield c
