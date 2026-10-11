"""The real app plus a slow route, to have a request in flight when the shutdown test sends SIGTERM."""

import asyncio

from app.main import create_app

app = create_app()


@app.get("/slow")
async def slow() -> dict:
    await asyncio.sleep(2)
    return {"done": True}
