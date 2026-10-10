import math

import pytest

from app.config import Settings
from app.domain.geo import BoundingBox, is_valid_radius, is_within_bogota, same_point

BOGOTA = Settings().bogota
MAX_RADIUS = Settings().max_radius_m


def test_default_settings_match_plan():
    assert BOGOTA == BoundingBox(min_lat=3.72, max_lat=4.84, min_lon=-74.46, max_lon=-73.98)
    assert MAX_RADIUS == 6000
    assert Settings().db_pool_max == 50


@pytest.mark.parametrize(
    "lat, lon",
    [
        (4.6512, -74.0561),  # Chapinero
        (4.0, -74.2),  # Sumapaz (rural)
        (3.72, -74.46),  # south-west corner (inclusive)
        (4.84, -73.98),  # north-east corner (inclusive)
    ],
)
def test_points_inside_bogota(lat, lon):
    assert is_within_bogota(lat, lon, BOGOTA)


@pytest.mark.parametrize(
    "lat, lon",
    [
        (6.2442, -75.5812),  # Medellín
        (3.7199, -74.2),  # just south
        (4.8401, -74.2),  # just north
        (4.6, -74.4601),  # just west
        (4.6, -73.9799),  # just east
        (-4.6512, 74.0561),  # swapped signs
        (math.nan, -74.0),
        (4.6, math.inf),
    ],
)
def test_points_outside_bogota(lat, lon):
    assert not is_within_bogota(lat, lon, BOGOTA)


@pytest.mark.parametrize("radius", [0.1, 1, 500, 5999.9, 6000])
def test_valid_radius(radius):
    assert is_valid_radius(radius, MAX_RADIUS)


@pytest.mark.parametrize("radius", [0, -1, 6000.01, 6001, math.nan, math.inf])
def test_invalid_radius(radius):
    assert not is_valid_radius(radius, MAX_RADIUS)


def test_same_point_tolerates_float_noise_only():
    assert same_point(4.6512, -74.0561, 4.65120000001, -74.05609999999)
    assert not same_point(4.6512, -74.0561, 4.6513, -74.0561)
    assert not same_point(4.6512, -74.0561, 4.6512, -74.0562)
