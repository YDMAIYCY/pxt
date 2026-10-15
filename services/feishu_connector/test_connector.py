"""Contract tests use explicit fixtures. They are NOT live Feishu evidence."""
import asyncio
import base64
import hashlib
import time
from urllib.parse import parse_qs, urlparse

import httpx
import pytest
from cryptography.fernet import Fernet
from fastapi import HTTPException
from fastapi.testclient import TestClient

from feishu import Feishu, TOKEN_URL
from main import create_app
from store import Store, digest


@pytest.fixture
def store(tmp_path):
    vault = Store(tmp_path / "vault.db", Fernet.generate_key().decode())
    yield vault
    vault.db.close()


def seed(store, *, expired=False):
    store.create("session-fixture", "state-fixture", "v" * 43)
    key = digest("session-fixture")
    store.save_tokens(key, {"access_token": "access-fixture", "expires_in": -1 if expired else 3600,
                          "refresh_token": "refresh-fixture", "refresh_token_expires_in": 3600,
                          "scope": "docx:document:readonly offline_access"}, "tenant:user")
    return key


def test_vault_encryption_session_hash_and_one_time_state(store):
    store.create("sensitive-session", "random-state", "sensitive-verifier")
    raw = store.get(digest("sensitive-session"))
    assert "sensitive-verifier" not in str(raw)
    assert store.consume_state("bad-state") is None
    assert store.consume_state("random-state") == (digest("sensitive-session"), "sensitive-verifier")
    assert store.consume_state("random-state") is None
    store.save_tokens(digest("sensitive-session"), {"access_token": "secret-access", "expires_in": 60})
    assert b"secret-access" not in store.get(digest("sensitive-session"))["tokens"]


def test_state_expiry(store):
    store.create("s", "state", "verifier")
    store.db.execute("UPDATE connections SET state_expires=?", (time.time() - 1,))
    store.db.commit()
    assert store.consume_state("state") is None


def test_oauth_callback_cannot_be_replayed_and_tokens_are_not_exposed(store, monkeypatch):
    monkeypatch.setenv("FEISHU_APP_ID", "app-fixture")
    monkeypatch.setenv("FEISHU_REDIRECT_URI", "http://localhost:8787/oauth/feishu/callback")

    class CallbackApi(Feishu):
        async def exchange(self, **payload):
            assert payload["redirect_uri"].endswith("/oauth/feishu/callback")
            assert len(payload["code_verifier"]) >= 43
            actual = base64.urlsafe_b64encode(hashlib.sha256(payload['code_verifier'].encode()).digest()).rstrip(b'=').decode()
            assert actual == query['code_challenge'][0]
            return {"access_token": "access-fixture", "expires_in": 3600, "scope": "docx:document:readonly"}

        async def request(self, *args, **kwargs):
            return {"open_id": "user-fixture", "tenant_key": "tenant-fixture"}

    client = TestClient(create_app(store, CallbackApi(store, "id", "secret")))
    assert client.get("/connection").status_code == 401
    started = client.post("/oauth/feishu/start").json()
    query = parse_qs(urlparse(started["authorization_url"]).query)
    assert query["code_challenge_method"] == ["S256"]
    callback = {"state": query["state"][0], "code": "code-fixture"}
    assert client.get("/oauth/feishu/callback", params=callback).status_code == 200
    assert client.get("/oauth/feishu/callback", params=callback).status_code == 400
    headers = {"Authorization": "Bearer " + started["session_token"]}
    status = client.get("/connection", headers=headers)
    assert status.json()["status"] == "connected"
    assert "access-fixture" not in status.text
    assert status.json()["can_refresh"] is False
    assert status.headers["cache-control"] == "no-store"
    assert client.delete("/connection", headers=headers).status_code == 200
    assert client.get("/connection", headers=headers).status_code == 401


def test_refresh_is_serialized_and_rotated(store):
    key = seed(store, expired=True)

    class RefreshApi(Feishu):
        calls = 0

        async def exchange(self, **payload):
            self.calls += 1
            assert payload["refresh_token"] == "refresh-fixture"
            await asyncio.sleep(0)
            return {"access_token": "renewed", "refresh_token": "rotated", "expires_in": 3600,
                    "refresh_token_expires_in": 7200}

    api = RefreshApi(store, "id", "secret")

    async def run():
        return await asyncio.gather(api.access_token(key), api.access_token(key))

    assert asyncio.run(run()) == ["renewed", "renewed"]
    assert api.calls == 1
    assert store.tokens(store.get(key))["refresh_token"] == "rotated"


def test_missing_offline_access_requires_reconnect(store):
    key = seed(store)
    store.save_tokens(key, {"access_token": "fixture", "expires_in": -1})
    with pytest.raises(HTTPException) as failure:
        asyncio.run(Feishu(store, "id", "secret").access_token(key))
    assert failure.value.status_code == 401


def test_pages_follow_all_cursors_and_reject_broken_pagination(store):
    class Paged(Feishu):
        async def request(self, key, method, path, **kwargs):
            if kwargs["params"].get("page_token") == "next":
                return {"items": [2], "has_more": False}
            return {"items": [1], "has_more": True, "page_token": "next"}

    assert asyncio.run(Paged(store, "id", "secret").pages("key", "/path", "items")) == [1, 2]

    class Broken(Paged):
        async def request(self, *args, **kwargs):
            return {"items": [], "has_more": True}

    with pytest.raises(HTTPException):
        asyncio.run(Broken(store, "id", "secret").pages("key", "/path", "items"))


@pytest.mark.parametrize("status,code,expected", [(200, 99991668, 401), (200, 91204, 403), (403, 1061004, 403), (429, 99991400, 429)])
def test_upstream_error_mapping(store, monkeypatch, status, code, expected):
    original = httpx.AsyncClient
    transport = httpx.MockTransport(lambda request: httpx.Response(status, json={"code": code, "msg": "fixture"}))
    monkeypatch.setattr(httpx, "AsyncClient", lambda **kwargs: original(transport=transport, **kwargs))
    with pytest.raises(HTTPException) as failure:
        asyncio.run(Feishu(store, "id", "secret").send("GET", "https://open.feishu.cn/open-apis/drive/v1/files"))
    assert failure.value.status_code == expected
    assert failure.value.detail["feishu_code"] == code
    assert failure.value.detail["upstream_http_status"] == status


def test_documented_pkce_compatible_endpoint_is_configured():
    assert TOKEN_URL == "https://open.feishu.cn/open-apis/authen/v2/oauth/token"


def test_import_rejects_foreign_document_and_reports_partial_failure(store):
    seed(store)

    class ImportApi(Feishu):
        async def folder(self, *args):
            return {"name": "fixture folder"}

        async def files(self, *args):
            return [{"token": "DocA", "type": "docx", "modified_time": "123", "url": "https://tenant.feishu.cn/docx/DocA"},
                    {"token": "DocB", "type": "docx"}]

        async def document(self, key, token):
            if token == "DocB":
                raise HTTPException(403, {"message": "fixture permission failure"})
            return {"document_id": token, "title": "fixture", "text": "fixture", "blocks": [], "revision_id": 1}

    client = TestClient(create_app(store, ImportApi(store, "id", "secret")))
    headers = {"Authorization": "Bearer session-fixture"}
    body = {"container_type": "folder", "container_id": "Folder", "document_ids": ["Foreign"]}
    assert client.post("/imports/read", headers=headers, json=body).status_code == 422
    body["document_ids"] = ["DocA", "DocA", "DocB"]
    response = client.post("/imports/read", headers=headers, json=body).json()
    assert len(response["documents"]) == len(response["failures"]) == 1
    assert response["documents"][0]["modified_time"] == "123"
    assert response["documents"][0]["source_url"].endswith("/docx/DocA")
