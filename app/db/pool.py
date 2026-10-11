"""asyncpg connection pool lifecycle. The pool is the only state shared between requests."""

import logging

import asyncpg

from app.config import Settings

CONNECT_TIMEOUT_S = 5

logger = logging.getLogger(__name__)


async def create_pool(settings: Settings) -> asyncpg.Pool:
    return await asyncpg.create_pool(
        dsn=settings.database_url,
        min_size=settings.db_pool_min,
        max_size=settings.db_pool_max,
        timeout=CONNECT_TIMEOUT_S,
    )


async def close_pool(pool: asyncpg.Pool) -> None:
    await pool.close()
    logger.info("database pool closed")
