def test_health(client):
    assert client.get("/health").json() == {"status": "UP"}


def test_ready_checks_database(client):
    response = client.get("/ready")
    assert response.status_code == 200
    assert response.json() == {"status": "READY"}


def test_root(client):
    body = client.get("/").json()
    assert body["service"] == "TaskBoard API"
    assert "version" in body


def test_create_and_get_task(client):
    created = client.post("/api/tasks", json={"title": "Deploy application", "priority": "HIGH", "assignee": "Student"})
    assert created.status_code == 201
    task = created.json()
    assert task["title"] == "Deploy application"
    assert task["status"] == "TODO"
    fetched = client.get(f"/api/tasks/{task['id']}")
    assert fetched.status_code == 200
    assert fetched.json()["priority"] == "HIGH"


def test_list_tasks_newest_first(client):
    client.post("/api/tasks", json={"title": "first"})
    client.post("/api/tasks", json={"title": "second"})
    titles = [t["title"] for t in client.get("/api/tasks").json()]
    assert titles == ["second", "first"]


def test_update_task_status(client):
    task = client.post("/api/tasks", json={"title": "Write tests"}).json()
    updated = client.put(f"/api/tasks/{task['id']}", json={"status": "IN_PROGRESS"})
    assert updated.status_code == 200
    assert updated.json()["status"] == "IN_PROGRESS"
    assert updated.json()["title"] == "Write tests"  # untouched fields are kept


def test_delete_task(client):
    task = client.post("/api/tasks", json={"title": "Temporary"}).json()
    assert client.delete(f"/api/tasks/{task['id']}").status_code == 204
    assert client.get(f"/api/tasks/{task['id']}").status_code == 404


def test_stats(client):
    client.post("/api/tasks", json={"title": "a", "status": "TODO"})
    client.post("/api/tasks", json={"title": "b", "status": "DONE"})
    client.post("/api/tasks", json={"title": "c", "status": "DONE"})
    assert client.get("/api/tasks/stats").json() == {"total": 3, "todo": 1, "inProgress": 0, "done": 2}


def test_validation_errors(client):
    assert client.post("/api/tasks", json={"title": ""}).status_code == 422
    assert client.post("/api/tasks", json={"title": "x", "priority": "URGENT"}).status_code == 422


def test_not_found(client):
    assert client.get("/api/tasks/99999").status_code == 404
    assert client.put("/api/tasks/99999", json={"title": "x"}).status_code == 404
    assert client.delete("/api/tasks/99999").status_code == 404


def test_metrics_exposed(client):
    client.get("/health")
    response = client.get("/metrics")
    assert response.status_code == 200
    assert "http_requests_total" in response.text
