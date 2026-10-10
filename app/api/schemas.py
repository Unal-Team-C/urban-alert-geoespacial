"""Request/response models of the geospatial contract (camelCase JSON, English names)."""

from uuid import UUID

from pydantic import BaseModel, ConfigDict, model_validator
from pydantic.alias_generators import to_camel

from app.config import get_settings
from app.domain.geo import is_valid_radius, is_within_bogota


class CamelModel(BaseModel):
    model_config = ConfigDict(alias_generator=to_camel, populate_by_name=True)


def _check_bogota(lat: float, lon: float) -> None:
    if not is_within_bogota(lat, lon, get_settings().bogota):
        raise ValueError("coordinate is outside the Bogotá range")


class Coordinate(CamelModel):
    lat: float
    lon: float


class BogotaCoordinate(Coordinate):
    """Input coordinate: must lie inside the configured Bogotá range."""

    @model_validator(mode="after")
    def _inside_bogota(self) -> "BogotaCoordinate":
        _check_bogota(self.lat, self.lon)
        return self


class AssignLocation(CamelModel):
    report_id: UUID
    coordinate: BogotaCoordinate


class LocationAssigned(CamelModel):
    coordinate_id: UUID
    report_id: UUID
    coordinate: Coordinate


class NearbyReport(CamelModel):
    report_id: UUID
    coordinate_id: UUID
    coordinate: Coordinate


class NearbyQuery(BaseModel):
    """Query parameters of GET /reports: lat, lon and radius in meters."""

    lat: float
    lon: float
    radius: float

    @model_validator(mode="after")
    def _check(self) -> "NearbyQuery":
        _check_bogota(self.lat, self.lon)
        max_radius = get_settings().max_radius_m
        if not is_valid_radius(self.radius, max_radius):
            raise ValueError(f"radius must be greater than 0 and at most {max_radius:g} meters")
        return self


class ErrorDetail(BaseModel):
    field: str
    reason: str


class ErrorResponse(BaseModel):
    code: int
    message: str
    details: list[ErrorDetail] | None = None
