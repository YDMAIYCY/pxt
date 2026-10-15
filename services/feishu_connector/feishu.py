import asyncio
import time
from email.utils import parsedate_to_datetime
from urllib.parse import quote

import httpx
from fastapi import HTTPException

from store import Store

API = "https://open.feishu.cn/open-apis"
# The documented authen/v1 authorize flow currently pairs PKCE with this endpoint.
# Keep PKCE and client authentication; do not retry a rejected code without either.
TOKEN_URL = "https://open.feishu.cn/open-apis/authen/v2/oauth/token"
EXPIRED_CODES = {99991661, 99991663, 99991668, 1061005}


class Feishu:
    def __init__(self, store: Store, app_id: str, secret: str):
        self.store, self.app_id, self.secret = store, app_id, secret
        self.locks: dict[str, asyncio.Lock] = {}
        self.rate_limit_until = 0.0

    async def send(self, method: str, url: str, **kwargs) -> dict:
        remaining = self.rate_limit_until - time.time()
        if remaining > 30:
            raise HTTPException(429, {"message": "飞书限流，请按提示稍后重试", "retry_after": int(remaining) + 1})
        if remaining > 0:
            await asyncio.sleep(remaining)
        try:
            async with httpx.AsyncClient(timeout=30) as client:
                for attempt in range(4):
                    response = await client.request(method, url, **kwargs)
                    body = response.json()
                    if response.status_code != 429 and body.get('code') != 99991400:
                        break
                    hint = response.headers.get('Retry-After', '')
                    try:
                        delay = float(hint)
                    except ValueError:
                        try:
                            delay = parsedate_to_datetime(hint).timestamp() - time.time()
                        except (ValueError, TypeError):
                            delay = 0.5 * 2 ** attempt
                    delay = max(0, delay)
                    self.rate_limit_until = time.time() + delay
                    if attempt == 3 or delay > 30:
                        break
                    await asyncio.sleep(delay)
        except (httpx.HTTPError, ValueError):
            raise HTTPException(502, {"message": "飞书网络请求失败或响应无法解析"}) from None
        code = body.get("code", 0)
        if response.is_error or code != 0 or body.get("error"):
            status = response.status_code if response.is_error else 502
            if code in EXPIRED_CODES:
                status = 401
            if code in {99991671, 99991672, 1061004, 91204, 1770032}:
                status = 403
            if code == 99991400:
                status = 429
            message = {401: "飞书 Token 已失效，请重新连接", 403: "缺少用户身份权限或无权访问该资源", 404: "资源不存在或已删除", 429: "飞书限流，请稍后重试"}.get(status, "飞书 API 调用失败")
            if code == 20049:
                message = "飞书授权校验失败，请返回 App 重新连接"
            raise HTTPException(status, {"message": message, "upstream_http_status": response.status_code,
                                         "feishu_code": code, "retry_after": max(0, int(self.rate_limit_until-time.time())+1),
                                         "log_id": response.headers.get("x-tt-logid")})
        return body

    async def exchange(self, **payload) -> dict:
        return await self.send("POST", TOKEN_URL, json={"client_id": self.app_id, "client_secret": self.secret, **payload})

    async def access_token(self, key: str, rejected_token: str | None = None) -> str:
        async with self.locks.setdefault(key, asyncio.Lock()):
            row = self.store.get(key)
            if not row or row["status"] != "connected" or not row["tokens"]:
                raise HTTPException(401, {"message": "请先完成飞书授权"})
            tokens = self.store.tokens(row)
            if tokens["expires_at"] > time.time() + 60 and (rejected_token is None or tokens["access_token"] != rejected_token):
                return tokens["access_token"]
            if not tokens.get("refresh_token") or tokens["refresh_expires_at"] <= time.time():
                self.store.fail(key, "授权已过期，请重新连接；持续同步需要 offline_access")
                raise HTTPException(401, {"message": "授权已过期，请重新连接；持续同步需要 offline_access"})
            try:
                renewed = await self.exchange(grant_type="refresh_token", refresh_token=tokens["refresh_token"])
            except HTTPException as error:
                # Only definitive rejection invalidates the connection; network failures can be retried.
                if error.status_code < 500 and error.status_code not in (408, 429):
                    self.store.fail(key, "刷新授权失败，请重新连接")
                raise
            renewed.setdefault("scope", tokens.get("scope", ""))
            self.store.save_tokens(key, renewed)
            return renewed["access_token"]

    async def request(self, key: str, method: str, path: str, **kwargs) -> dict:
        token = await self.access_token(key)
        try:
            result = await self.send(method, API + path, headers={"Authorization": "Bearer " + token}, **kwargs)
        except HTTPException as error:
            if error.status_code != 401:
                raise
            token = await self.access_token(key, rejected_token=token)
            result = await self.send(method, API + path, headers={"Authorization": "Bearer " + token}, **kwargs)
        return result.get("data", {})

    async def pages(self, key: str, path: str, field: str, **params) -> list:
        items, seen = [], set()
        while True:
            data = await self.request(key, "GET", path, params={"page_size": 200, **params})
            items.extend(data.get(field, []))
            if not data.get("has_more"):
                return items
            token = data.get("page_token")
            if not token or token in seen:
                raise HTTPException(502, {"message": "飞书分页游标异常，未返回完整结果"})
            seen.add(token)
            params["page_token"] = token

    async def folder(self, key: str, token: str) -> dict:
        return await self.request(key, "GET", "/drive/explorer/v2/folder/" + quote(token, safe="") + "/meta")

    async def files(self, key: str, token: str) -> list:
        return await self.pages(key, "/drive/v1/files", "files", folder_token=token)

    async def document(self, key: str, token: str) -> dict:
        path = "/docx/v1/documents/" + quote(token, safe="")
        for _ in range(2):
            meta = (await self.request(key, "GET", path))["document"]
            # Historical versions require edit permission. Read latest and verify revision afterwards.
            blocks = await self.pages(key, path + "/blocks", "items", page_size=500, document_revision_id=-1)
            raw = await self.request(key, "GET", path + "/raw_content")
            after = (await self.request(key, "GET", path))["document"]
            if meta["revision_id"] == after["revision_id"]:
                return {"document_id": token, "title": meta["title"], "revision_id": meta["revision_id"],
                        "text": raw["content"], "blocks": blocks,
                        "warnings": ["图片、附件等非文字块仅保留结构，第一阶段不下载附件或 OCR 图片"]}
        raise HTTPException(409, {"message": "文档读取期间持续变化，请稍后重新同步"})
