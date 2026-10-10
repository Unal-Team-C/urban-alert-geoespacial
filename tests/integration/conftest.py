import pytest
from fastapi import FastAPI


@pytest.fixture(autouse=True)
async def clean_coordinates(app: FastAPI) -> None:
    """Every integration test starts with an empty coordinates table (test database only)."""
    async with app.state.pool.acquire() as connection:
        await connection.execute("TRUNCATE coordinates")
