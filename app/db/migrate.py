"""Applies db/schema.sql and the application role. Run with: python -m app.db.migrate

Runs as the database master user (in AWS, an ECS one-off task). Idempotent: running it again changes nothing,
except re-synchronizing the application role's password with the secret.
"""

import asyncio
import logging
import os
import sys
from dataclasses import dataclass
from pathlib import Path

import asyncpg

from app.observability import configure_logging

logger = logging.getLogger(__name__)

CONNECT_TIMEOUT_S = 10


@dataclass(frozen=True)
class MigrationSettings:
    host: str
    port: int
    dbname: str
    admin_user: str
    admin_password: str
    app_user: str
    app_password: str
    sslmode: str = "require"
    schema_path: str = "/srv/db/schema.sql"

    @classmethod
    def from_env(cls) -> "MigrationSettings":
        env = os.environ
        return cls(
            host=env["DB_HOST"],
            port=int(env.get("DB_PORT", "5432")),
            dbname=env["DB_NAME"],
            admin_user=env["DB_ADMIN_USER"],
            admin_password=env["DB_ADMIN_PASSWORD"],
            app_user=env["DB_APP_USER"],
            app_password=env["DB_APP_PASSWORD"],
            sslmode=env.get("DB_SSLMODE", "require"),
            schema_path=env.get("SCHEMA_PATH", "/srv/db/schema.sql"),
        )


async def migrate(settings: MigrationSettings) -> None:
    schema = Path(settings.schema_path).read_text()
    conn = await asyncpg.connect(
        host=settings.host,
        port=settings.port,
        database=settings.dbname,
        user=settings.admin_user,
        password=settings.admin_password,
        ssl=settings.sslmode,
        timeout=CONNECT_TIMEOUT_S,
    )
    try:
        async with conn.transaction():
            await conn.execute(schema)
            await _ensure_app_role(conn, settings)
    finally:
        await conn.close()
    logger.info("schema applied", extra={"database": settings.dbname, "app_user": settings.app_user})


async def _ensure_app_role(conn: asyncpg.Connection, settings: MigrationSettings) -> None:
    # Identifiers and the password cannot be bind parameters in DDL: quote them in the server with format().
    role = settings.app_user
    exists = await conn.fetchval("SELECT 1 FROM pg_roles WHERE rolname = $1", role)
    if not exists:
        await conn.execute(await conn.fetchval("SELECT format('CREATE ROLE %I LOGIN', $1::text)", role))
    await conn.execute(
        await conn.fetchval("SELECT format('ALTER ROLE %I WITH LOGIN PASSWORD %L', $1::text, $2::text)", role, settings.app_password)
    )
    for statement in (
        "SELECT format('GRANT CONNECT ON DATABASE %I TO %I', $2::text, $1::text)",
        "SELECT format('GRANT USAGE ON SCHEMA public TO %I', $1::text)",
        "SELECT format('REVOKE ALL ON coordinates FROM %I', $1::text)",
        "SELECT format('GRANT SELECT, INSERT ON coordinates TO %I', $1::text)",
    ):
        args = (role, settings.dbname) if "$2" in statement else (role,)
        await conn.execute(await conn.fetchval(statement, *args))


def main() -> int:
    configure_logging()
    try:
        asyncio.run(migrate(MigrationSettings.from_env()))
    except Exception:
        logger.exception("schema migration failed")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
