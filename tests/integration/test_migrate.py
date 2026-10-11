"""app.db.migrate against geospatial_test. The compose test user is a superuser, standing in for the RDS master user."""

import os
from dataclasses import replace
from urllib.parse import urlparse

import asyncpg
import pytest

from app.db.migrate import MigrationSettings, migrate

APP_USER = "geospatial_app_test"


@pytest.fixture
def settings() -> MigrationSettings:
    url = urlparse(os.environ["DATABASE_URL"])
    return MigrationSettings(
        host=url.hostname,
        port=url.port or 5432,
        dbname=url.path.lstrip("/"),
        admin_user=url.username,
        admin_password=url.password,
        app_user=APP_USER,
        app_password="first-password",
        sslmode="disable",
        schema_path=os.environ.get("SCHEMA_PATH", "/srv/db/schema.sql"),
    )


async def connect(settings: MigrationSettings, user: str, password: str) -> asyncpg.Connection:
    return await asyncpg.connect(
        host=settings.host, port=settings.port, database=settings.dbname, user=user, password=password, ssl=False
    )


async def admin(settings: MigrationSettings) -> asyncpg.Connection:
    return await connect(settings, settings.admin_user, settings.admin_password)


async def test_migrate_applies_schema(settings: MigrationSettings):
    await migrate(settings)

    conn = await admin(settings)
    try:
        assert await conn.fetchval("SELECT count(*) FROM pg_extension WHERE extname = 'postgis'") == 1
        assert await conn.fetchval("SELECT to_regclass('public.coordinates') IS NOT NULL")
        assert await conn.fetchval("SELECT to_regclass('public.coordinates_location_gix') IS NOT NULL")
    finally:
        await conn.close()


async def test_migrate_twice_is_a_no_op(settings: MigrationSettings):
    await migrate(settings)
    await migrate(settings)

    conn = await admin(settings)
    try:
        assert await conn.fetchval("SELECT count(*) FROM pg_roles WHERE rolname = $1", APP_USER) == 1
    finally:
        await conn.close()


@pytest.mark.parametrize(
    ("privilege", "granted"),
    [("SELECT", True), ("INSERT", True), ("UPDATE", False), ("DELETE", False), ("TRUNCATE", False)],
)
async def test_app_user_can_only_read_and_insert(settings: MigrationSettings, privilege: str, granted: bool):
    await migrate(settings)

    conn = await admin(settings)
    try:
        assert await conn.fetchval("SELECT has_table_privilege($1, 'coordinates', $2)", APP_USER, privilege) is granted
    finally:
        await conn.close()


async def test_app_user_cannot_change_the_schema(settings: MigrationSettings):
    await migrate(settings)

    conn = await connect(settings, APP_USER, settings.app_password)
    try:
        with pytest.raises(asyncpg.InsufficientPrivilegeError):
            await conn.execute("DROP TABLE coordinates")
        with pytest.raises(asyncpg.InsufficientPrivilegeError):
            await conn.execute("CREATE TABLE intruder (id int)")
    finally:
        await conn.close()


async def test_app_password_is_synchronized(settings: MigrationSettings):
    await migrate(settings)
    rotated = replace(settings, app_password="second-'password\"")
    await migrate(rotated)

    conn = await connect(settings, APP_USER, rotated.app_password)
    await conn.close()
    with pytest.raises(asyncpg.InvalidPasswordError):
        await connect(settings, APP_USER, settings.app_password)


async def test_sslmode_require_refuses_an_unencrypted_server(settings: MigrationSettings):
    # The local test database has no TLS: requiring it must fail instead of falling back to plain text.
    with pytest.raises((ConnectionError, OSError, asyncpg.PostgresError)):
        await migrate(replace(settings, sslmode="require"))
