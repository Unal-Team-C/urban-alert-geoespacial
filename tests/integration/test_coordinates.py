from uuid import uuid4

import httpx

URL = "/api/v1/geospatial/coordinates"
CHAPINERO = {"lat": 4.6512, "lon": -74.0561}


async def test_existing_coordinate_is_resolved(client: httpx.AsyncClient):
    report_id = str(uuid4())
    created = (await client.post(URL, json={"reportId": report_id, "coordinate": CHAPINERO})).json()

    response = await client.get(f"{URL}/{created['coordinateId']}")

    assert response.status_code == 200
    assert response.json() == {"coordinateId": created["coordinateId"], "reportId": report_id, "coordinate": CHAPINERO}


async def test_unknown_coordinate_returns_404(client: httpx.AsyncClient):
    response = await client.get(f"{URL}/{uuid4()}")

    assert response.status_code == 404
    assert response.json() == {"code": 404, "message": "Coordinate not found"}


async def test_malformed_coordinate_id_returns_400(client: httpx.AsyncClient):
    response = await client.get(f"{URL}/not-a-uuid")

    assert response.status_code == 400
    assert response.json()["details"][0]["field"] == "coordinateId"
