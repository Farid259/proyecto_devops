import pytest
from fastapi.testclient import TestClient
from prometheus_client.parser import text_string_to_metric_families

from app.main import create_app


@pytest.fixture
def client():
    with TestClient(create_app()) as test_client:
        yield test_client


def test_index(client):
    response = client.get("/")
    assert response.status_code == 200
    assert response.json()["name"] == "DevOps Temperature API"


def test_health(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


@pytest.mark.parametrize(
    "celsius,fahrenheit,kelvin",
    [(0, 32, 273.15), (20, 68, 293.15), (-40, -40, 233.15),
     (100, 212, 373.15), (-273.15, -459.67, 0), (36.6, 97.88, 309.75)],
)
def test_conversion(client, celsius, fahrenheit, kelvin):
    response = client.get("/api/convert", params={"celsius": celsius})
    assert response.status_code == 200
    assert response.json() == {
        "celsius": celsius, "fahrenheit": fahrenheit, "kelvin": kelvin
    }


@pytest.mark.parametrize("value", ["texto", "", "NaN", "inf", "-inf", "-273.16", "1000001"])
def test_invalid_temperature(client, value):
    response = client.get("/api/convert", params={"celsius": value})
    assert response.status_code == 422
    assert response.json()["detail"][0]["loc"] == ["query", "celsius"]


def test_missing_temperature(client):
    assert client.get("/api/convert").status_code == 422


def test_documentation(client):
    assert client.get("/docs").status_code == 200
    schema = client.get("/openapi.json").json()
    assert "/api/convert" in schema["paths"]


def test_metrics_record_success_errors_and_duration(client):
    client.get("/api/convert", params={"celsius": 20})
    client.get("/api/convert", params={"celsius": "invalid"})
    client.get("/missing-one")
    client.get("/missing-two")
    response = client.get("/metrics")
    assert response.status_code == 200
    assert response.headers["content-type"].startswith("text/plain")
    samples = [sample for family in text_string_to_metric_families(response.text)
               for sample in family.samples]
    counters = {(s.labels["route"], s.labels["status"]): s.value
                for s in samples if s.name == "http_requests_total"}
    assert counters == {("/api/convert", "200"): 1, ("/api/convert", "422"): 1,
                        ("unmatched", "404"): 2}
    counts = {s.labels["route"]: s.value for s in samples
              if s.name == "http_request_duration_seconds_count"}
    assert counts["/api/convert"] == 2
    # Las lecturas sucesivas de /metrics no alteran los contadores.
    assert client.get("/metrics").text == response.text
