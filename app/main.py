"""FastAPI application factory. Run with: uvicorn app.main:app"""

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI

from app.api.errors import register_error_handlers
from app.api.routes import health_router, router
from app.config import Settings, get_settings
from app.db.pool import close_pool, create_pool


def create_app(settings: Settings | None = None) -> FastAPI:
    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncIterator[None]:
        app.state.pool = await create_pool(settings or get_settings())
        try:
            yield
        finally:
            await close_pool(app.state.pool)

    app = FastAPI(
        title="UrbanAlert Geospatial Service",
        version="0.1.0",
        summary="Location assignment and nearby-report queries for UrbanAlert.",
        lifespan=lifespan,
    )
    register_error_handlers(app)
    app.include_router(health_router)
    app.include_router(router)
    return app


app = create_app()
