import pytest

from app.main import app


@pytest.fixture
def client():
    app.config["TESTING"] = True
    return app.test_client()


def test_health(client):
    res = client.get("/health")
    assert res.status_code == 200
    assert res.get_json()["status"] == "ok"


def test_index(client):
    assert "CI/CD demo" in client.get("/").get_json()["message"]


@pytest.mark.parametrize(
    "op,a,b,expected",
    [("add", 2, 3, 5), ("subtract", 9, 4, 5), ("multiply", 3, 3, 9), ("divide", 9, 3, 3)],
)
def test_operations(client, op, a, b, expected):
    res = client.get(f"/api/{op}?a={a}&b={b}")
    assert res.status_code == 200
    assert res.get_json()["result"] == expected


def test_divide_by_zero_returns_400(client):
    assert client.get("/api/divide?a=1&b=0").status_code == 400


def test_bad_input_returns_400(client):
    assert client.get("/api/add?a=x&b=1").status_code == 400


def test_unknown_operation_returns_404(client):
    assert client.get("/api/power?a=2&b=3").status_code == 404
