"""Offline contract fixtures, never evidence of a successful real Feishu call."""
import asyncio
import httpx
import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient

from feishu import Feishu
from main import create_app
from test_connector import store, seed


class TreeApi(Feishu):
    async def folder(self, key, token):
        return {"name": token}

    async def files(self, key, token):
        if token == "root":
            return [{"token": "nested", "type": "folder", "name": "sub"},
                    {"token": "A", "type": "docx", "name": "first"}]
        return [{"token": "B", "type": "docx", "name": "second"},
                {"token": "C", "type": "docx", "name": "third"},
                {"token": "sheet", "type": "sheet", "name": "unsupported"}]

    async def document(self, *args):
        raise AssertionError("Metadata scan must not read document content")


def scan_client(store):
    seed(store)
    return TestClient(create_app(store, TreeApi(store, "id", "secret")))


def test_nested_folders_are_one_container_and_overlapping_selections_collapse(store):
    response = scan_client(store).post("/imports/scan", headers={"Authorization": "Bearer session-fixture"},
                                      json={"roots": [{"kind": "folder", "id": "root"},
                                                      {"kind": "folder", "id": "nested"}]})
    assert response.status_code == 200
    plan = response.json()
    assert len(plan["roots"]) == 1
    assert len(plan["roots"][0]["documents"]) == 3
    assert plan["roots"][0]["documents"][0]["relative_path"] == "sub/second"
    assert plan["covered_selections"] == ["folder:nested"]
    assert plan["content_access_checked"] is False


def test_excluded_folder_with_one_reincluded_document(store):
    plan = scan_client(store).post("/imports/scan", headers={"Authorization": "Bearer session-fixture"},
                                  json={"roots": [{"kind": "folder", "id": "root",
                                                   "excluded": ["folder:nested"], "included": ["docx:B"]}]}).json()
    assert {d["document_id"] for d in plan["roots"][0]["documents"]} == {"A", "B"}


def test_existing_only_sync_freezes_document_ids(store):
    plan = scan_client(store).post("/imports/scan", headers={"Authorization": "Bearer session-fixture"},
                                  json={"roots": [{"kind": "folder", "id": "root", "document_ids": ["A"]}]}).json()
    assert [d["document_id"] for d in plan["roots"][0]["documents"]] == ["A"]


def test_long_retry_after_is_exposed_without_early_retry(store, monkeypatch):
    original = httpx.AsyncClient
    calls = []
    def response(request):
        calls.append(request)
        return httpx.Response(429, json={"code": 99991400}, headers={"Retry-After": "90"})
    monkeypatch.setattr(httpx, "AsyncClient", lambda **kwargs: original(transport=httpx.MockTransport(response), **kwargs))
    with pytest.raises(HTTPException) as failure:
        asyncio.run(Feishu(store, "id", "secret").send("GET", "https://open.feishu.cn/open-apis/drive/v1/files"))
    assert len(calls) == 1
    assert failure.value.status_code == 429
    assert failure.value.detail["retry_after"] >= 89


def test_rate_limited_refresh_does_not_destroy_provider_grant(store):
    key = seed(store, expired=True)
    class Limited(Feishu):
        async def exchange(self, **payload):
            raise HTTPException(429, {"message": "fixture limited", "retry_after": 90})
    with pytest.raises(HTTPException):
        asyncio.run(Limited(store, "id", "secret").access_token(key))
    assert store.get(key)["status"] == "connected"
    assert store.tokens(store.get(key))["refresh_token"] == "refresh-fixture"
