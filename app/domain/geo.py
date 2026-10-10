"""Pure geographic rules: Bogotá range and query radius limits (no FastAPI, no database)."""

import math
from dataclasses import dataclass


@dataclass(frozen=True)
class BoundingBox:
    min_lat: float
    max_lat: float
    min_lon: float
    max_lon: float

    def contains(self, lat: float, lon: float) -> bool:
        """Inclusive on every edge."""
        if not (math.isfinite(lat) and math.isfinite(lon)):
            return False
        return self.min_lat <= lat <= self.max_lat and self.min_lon <= lon <= self.max_lon


def is_within_bogota(lat: float, lon: float, bogota: BoundingBox) -> bool:
    return bogota.contains(lat, lon)


def is_valid_radius(radius_m: float, max_radius_m: float) -> bool:
    """A radius is valid when 0 < radius <= max_radius_m (meters)."""
    return math.isfinite(radius_m) and 0 < radius_m <= max_radius_m


SAME_POINT_DECIMALS = 7  # ~1 cm


def same_point(lat_a: float, lon_a: float, lat_b: float, lon_b: float) -> bool:
    """Two coordinates are the same location when they match to 7 decimal places."""
    return round(lat_a, SAME_POINT_DECIMALS) == round(lat_b, SAME_POINT_DECIMALS) and round(
        lon_a, SAME_POINT_DECIMALS
    ) == round(lon_b, SAME_POINT_DECIMALS)
