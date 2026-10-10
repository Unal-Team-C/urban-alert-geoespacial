from typing import Annotated
from uuid import UUID, uuid4

import httpx
import pytest
from fastapi import FastAPI, Query
from pydantic import ValidationError

from app.api.errors import ConflictError, CoordinateNotFoundError, ServiceUnavailableError, register_error_handlers
from app.api.schemas import AssignLocation, LocationAssigned, NearbyQuery, NearbyReport

INJECTION = "' OR 1=1 --"


def assign_payload(**overrides):
    payload = {"reportId": str(uuid4()), "coordinate": {"lat": 4.6512, "lon": -74.0561}}
    payload.update(overrides)
    return payload


# --- AssignLocation -------------------------------------------------------


def test_assign_location_accepts_contract_payload():
    model = AssignLocation.model_validate(assign_payload())
    assert isinstance(model.report_id, UUID)
    assert (model.coordinate.lat, model.coordinate.lon) == (4.6512, -74.0561)


@pytest.mark.parametrize(
    "payload",
    [
        assign_payload(coordinate={"lat": 6.2442, "lon": -75.5812}),  # outside Bogotá
        assign_payload(coordinate={"lat": 4.65}),  # lon missing
        assign_payload(coordinate={"lat": "abc", "lon": -74.05}),
        assign_payload(coordinate={"lat": INJECTION, "lon": -74.05}),
        assign_payload(reportId="not-a-uuid"),
        assign_payload(reportId=f"{uuid4()}; DROP TABLE coordinates"),
        {"coordinate": {"lat": 4.65, "lon": -74.05}},  # reportId missing
    ],
)
def test_assign_location_rejects_invalid_payloads(payload):
    with pytest.raises(ValidationError):
        AssignLocation.model_validate(payload)


def test_responses_serialize_in_camel_case_english():
    coordinate_id, report_id = uuid4(), uuid4()
    assigned = LocationAssigned(coordinate_id=coordinate_id, report_id=report_id, coordinate={"lat": 4.6, "lon": -74.1})
    assert assigned.model_dump(mode="json", by_alias=True) == {
        "coordinateId": str(coordinate_id),
        "reportId": str(report_id),
        "coordinate": {"lat": 4.6, "lon": -74.1},
    }
    nearby = NearbyReport(report_id=report_id, coordinate_id=coordinate_id, coordinate={"lat": 4.6, "lon": -74.1})
    assert set(nearby.model_dump(by_alias=True)) == {"reportId", "coordinateId", "coordinate"}


# --- NearbyQuery ----------------------------------------------------------


def test_nearby_query_accepts_valid_values():
    query = NearbyQuery(lat=4.6512, lon=-74.0561, radius=6000)
    assert query.radius == 6000


@pytest.mark.parametrize(
    "params",
    [
        {"lat": 4.6512, "lon": -74.0561, "radius": 6001},
        {"lat": 4.6512, "lon": -74.0561, "radius": 0},
        {"lat": 4.6512, "lon": -74.0561, "radius": -5},
        {"lat": 4.6512, "lon": -74.0561, "radius": "nan"},
        {"lat": 6.2442, "lon": -75.5812, "radius": 500},
        {"lat": INJECTION, "lon": -74.0561, "radius": 500},
        {"lat": 4.6512, "lon": -74.0561, "radius": INJECTION},
        {"lat": 4.6512, "lon": -74.0561},
    ],
)
def test_nearby_query_rejects_invalid_values(params):
    with pytest.raises(ValidationError):
        NearbyQuery.model_validate(params)


# --- Error handlers -------------------------------------------------------


@pytest.fixture(scope="module")
async def client():
    app = FastAPI()
    register_error_handlers(app)

    @app.get("/nearby")
    async def nearby(query: Annotated[NearbyQuery, Query()]):
        return {"ok": True}

    @app.post("/assign")
    async def assign(body: AssignLocation):
        return {"ok": True}

    @app.get("/missing")
    async def missing():
        raise CoordinateNotFoundError()

    @app.get("/conflict")
    async def conflict():
        raise ConflictError()

    @app.get("/down")
    async def down():
        raise ServiceUnavailableError()

    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as c:
        yield c


async def test_validation_error_is_400_without_echoing_input(client):
    response = await client.get("/nearby", params={"lat": INJECTION, "lon": -74.05, "radius": 500})
    assert response.status_code == 400
    body = response.json()
    assert body["code"] == 400
    assert body["message"] == "Invalid parameter"
    assert body["details"][0]["field"] == "lat"
    assert INJECTION not in response.text


async def test_radius_over_max_is_400(client):
    response = await client.get("/nearby", params={"lat": 4.65, "lon": -74.05, "radius": 6001})
    assert response.status_code == 400
    assert "6000" in response.json()["details"][0]["reason"]


async def test_invalid_body_is_400(client):
    response = await client.post("/assign", json=assign_payload(coordinate={"lat": 6.24, "lon": -75.58}))
    assert response.status_code == 400
    assert "Bogotá" in response.json()["details"][0]["reason"]


@pytest.mark.parametrize(
    "path, status, message",
    [
        ("/missing", 404, "Coordinate not found"),
        ("/conflict", 409, "Report already has a different location"),
        ("/down", 503, "Service unavailable"),
        ("/no-such-route", 404, "Not Found"),
    ],
)
async def test_domain_errors_are_normalized(client, path, status, message):
    response = await client.get(path)
    assert response.status_code == status
    assert response.json() == {"code": status, "message": message}
