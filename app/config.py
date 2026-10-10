"""Service settings, read from environment variables (see .env.example)."""

import os
from dataclasses import dataclass, field
from functools import lru_cache

from app.domain.geo import BoundingBox


def _float(name: str, default: float) -> float:
    return float(os.environ.get(name, default))


def _int(name: str, default: int) -> int:
    return int(os.environ.get(name, default))


@dataclass(frozen=True)
class Settings:
    database_url: str = "postgresql://geospatial:geospatial@db:5432/geospatial"
    db_pool_min: int = 5
    db_pool_max: int = 50
    max_radius_m: float = 6000
    bogota: BoundingBox = field(
        default_factory=lambda: BoundingBox(min_lat=3.72, max_lat=4.84, min_lon=-74.46, max_lon=-73.98)
    )


@lru_cache
def get_settings() -> Settings:
    defaults = Settings()
    return Settings(
        database_url=os.environ.get("DATABASE_URL", defaults.database_url),
        db_pool_min=_int("DB_POOL_MIN", defaults.db_pool_min),
        db_pool_max=_int("DB_POOL_MAX", defaults.db_pool_max),
        max_radius_m=_float("MAX_RADIUS_M", defaults.max_radius_m),
        bogota=BoundingBox(
            min_lat=_float("BOGOTA_MIN_LAT", defaults.bogota.min_lat),
            max_lat=_float("BOGOTA_MAX_LAT", defaults.bogota.max_lat),
            min_lon=_float("BOGOTA_MIN_LON", defaults.bogota.min_lon),
            max_lon=_float("BOGOTA_MAX_LON", defaults.bogota.max_lon),
        ),
    )
