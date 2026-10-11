import json
import logging
from collections.abc import Iterator

import httpx
import pytest
from fastapi import FastAPI

from app.observability import ACCESS_LOGGER, AccessLogMiddleware, JsonFormatter, configure_logging


class ListHandler(logging.Handler):
    """Collects formatted records so tests can parse what would reach stdout."""

    def __init__(self) -> None:
        super().__init__()
        self.setFormatter(JsonFormatter())
        self.lines: list[str] = []

    def emit(self, record: logging.LogRecord) -> None:
        self.lines.append(self.format(record))


@pytest.fixture
def access_lines() -> Iterator[list[str]]:
    handler = ListHandler()
    logger = logging.getLogger(ACCESS_LOGGER)
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)
    try:
        yield handler.lines
    finally:
        logger.removeHandler(handler)


def record(message: str, level: int = logging.INFO, **extra) -> logging.LogRecord:
    rec = logging.LogRecord("app.test", level, __file__, 1, message, None, None)
    rec.__dict__.update(extra)
    return rec


# --- JsonFormatter --------------------------------------------------------


def test_formatter_emits_one_json_object_with_base_fields():
    line = JsonFormatter().format(record("hello", logging.WARNING))

    assert "\n" not in line
    data = json.loads(line)
    assert data["level"] == "WARNING"
    assert data["logger"] == "app.test"
    assert data["message"] == "hello"
    assert data["timestamp"].endswith("Z")


def test_formatter_includes_extra_fields():
    data = json.loads(JsonFormatter().format(record("request", method="GET", status=200)))

    assert data["method"] == "GET"
    assert data["status"] == 200


def test_formatter_serializes_exceptions_in_a_single_line():
    try:
        raise ValueError("boom")
    except ValueError:
        import sys

        rec = logging.LogRecord("app.test", logging.ERROR, __file__, 1, "failed", None, sys.exc_info())

    line = JsonFormatter().format(rec)

    assert "\n" not in line
    data = json.loads(line)
    assert "ValueError: boom" in data["exception"]


def test_formatter_does_not_break_on_non_serializable_extras():
    data = json.loads(JsonFormatter().format(record("odd", thing=object())))

    assert data["thing"].startswith("<object object")


def test_configure_logging_installs_json_formatter_on_root_and_uvicorn():
    configure_logging()

    for name in ("", "uvicorn", "uvicorn.error"):
        logger = logging.getLogger(name)
        handlers = logger.handlers or logging.getLogger().handlers
        assert any(isinstance(h.formatter, JsonFormatter) for h in handlers), name


# --- AccessLogMiddleware --------------------------------------------------


def make_app() -> FastAPI:
    app = FastAPI()
    app.add_middleware(AccessLogMiddleware)

    @app.get("/ping")
    async def ping() -> dict:
        return {"ok": True}

    @app.get("/boom")
    async def boom() -> dict:
        raise RuntimeError("unexpected")

    return app


async def test_middleware_logs_one_line_per_request(access_lines: list[str]):
    transport = httpx.ASGITransport(app=make_app())
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.get("/ping", params={"secret": "do-not-log"})

    assert response.status_code == 200
    assert len(access_lines) == 1
    data = json.loads(access_lines[0])
    assert data["message"] == "request"
    assert data["method"] == "GET"
    assert data["path"] == "/ping"
    assert data["status"] == 200
    assert isinstance(data["duration_ms"], float)
    assert "do-not-log" not in access_lines[0]  # query strings are not logged


async def test_middleware_logs_unhandled_errors_as_500(access_lines: list[str]):
    transport = httpx.ASGITransport(app=make_app(), raise_app_exceptions=False)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.get("/boom")

    assert response.status_code == 500
    data = json.loads(access_lines[-1])
    assert data["path"] == "/boom"
    assert data["status"] == 500
    assert data["level"] == "ERROR"
