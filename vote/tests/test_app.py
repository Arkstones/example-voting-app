"""Unit tests for the vote app.

Run from the vote/ folder:
    pip install -r requirements-dev.txt
    pytest

Redis is replaced by fakeredis, an in-memory copy, so no real Redis is needed.
"""
import json
import os
import sys

import fakeredis
import pytest

# vote options must be set before app.py is imported, it reads them at import time
os.environ["OPTION_A"] = "Kampala"
os.environ["OPTION_B"] = "Entebbe"

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import app as vote_app  # noqa: E402


@pytest.fixture
def fake_redis(monkeypatch):
    server = fakeredis.FakeServer()

    def make_fake(host, db, socket_timeout):
        return fakeredis.FakeRedis(server=server, db=db)

    # app.py creates its client with Redis(host=..., db=0, socket_timeout=5)
    monkeypatch.setattr(vote_app, "Redis", make_fake)
    return fakeredis.FakeRedis(server=server)


@pytest.fixture
def client(fake_redis):
    vote_app.app.config["TESTING"] = True
    with vote_app.app.test_client() as client:
        yield client


def test_page_shows_both_options(client):
    response = client.get("/")
    assert response.status_code == 200
    assert b"Kampala vs Entebbe!" in response.data


def test_new_visitor_gets_a_voter_id_cookie(client):
    response = client.get("/")
    assert "voter_id=" in response.headers.get("Set-Cookie", "")


def test_vote_is_queued_in_redis(client, fake_redis):
    response = client.post("/", data={"vote": "a"})
    assert response.status_code == 200

    queued = fake_redis.lrange("votes", 0, -1)
    assert len(queued) == 1
    assert json.loads(queued[0])["vote"] == "a"


def test_same_voter_keeps_the_same_id(client, fake_redis):
    client.post("/", data={"vote": "a"})
    client.post("/", data={"vote": "b"})

    votes = [json.loads(v) for v in fake_redis.lrange("votes", 0, -1)]
    assert [v["vote"] for v in votes] == ["a", "b"]
    assert votes[0]["voter_id"] == votes[1]["voter_id"]


def test_get_request_does_not_queue_a_vote(client, fake_redis):
    client.get("/")
    assert fake_redis.llen("votes") == 0
