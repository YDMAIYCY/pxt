"""Single-worker, loopback-only development connector. See docs before deployment."""
import base64
import hashlib
import os
import re
import secrets
import time
from pathlib import Path
from html import escape
from urllib.parse import urlencode

from dotenv import load_dotenv
from fastapi import Depends, FastAPI, Header, HTTPException
from fastapi.responses import HTMLResponse
from pydantic import BaseModel

from feishu import Feishu
from store import Store, digest
from resources import register_resources

ROOT = Path(__file__).resolve().parent
load_dotenv(ROOT / ".env")
SCOPES = "docx:document:readonly drive:drive:readonly drive:drive.metadata:readonly wiki:wiki:readonly offline_access"


def create_app(vault: Store | None = None, api: Feishu | None = None) -> FastAPI:
    app = FastAPI(title="智学帮飞书连接服务")
    app_id = os.getenv("FEISHU_APP_ID", "")
    secret = os.getenv("FEISHU_APP_SECRET", "")
    redirect = os.getenv("FEISHU_REDIRECT_URI", "")
    key = os.getenv("FEISHU_TOKEN_ENCRYPTION_KEY", "")
    missing = [name for name, value in {"FEISHU_APP_ID": app_id, "FEISHU_APP_SECRET": secret,
               "FEISHU_REDIRECT_URI": redirect, "FEISHU_TOKEN_ENCRYPTION_KEY": key}.items() if not value]
    if vault is None and not missing:
        vault = Store(ROOT / "data" / "tokens.sqlite3", key)
    if api is None and vault:
        api = Feishu(vault, app_id, secret)

    def ready():
        if vault is None or api is None:
            raise HTTPException(503, {"message": "请先填写后端 .env", "missing": missing})

    def session(authorization: str = Header(default="")) -> str:
        ready()
        if not authorization.startswith("Bearer "):
            raise HTTPException(401, {"message": "缺少短期连接会话"})
        session_key = digest(authorization[7:])
        if not vault.get(session_key):
            raise HTTPException(401, {"message": "连接会话已过期，请重新授权"})
        return session_key

    @app.middleware("http")
    async def no_cache(request, call_next):
        response = await call_next(request)
        response.headers["Cache-Control"] = "no-store"
        response.headers["Referrer-Policy"] = "no-referrer"
        return response

    @app.get("/health")
    def health():
        return {"ready": vault is not None and api is not None, "missing": missing}

    @app.post("/oauth/feishu/start")
    async def start():
        ready()
        bearer, state, verifier = (secrets.token_urlsafe(32) for _ in range(3))
        vault.create(bearer, state, verifier)
        challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()
        url = "https://accounts.feishu.cn/open-apis/authen/v1/authorize?" + urlencode({
            "client_id": app_id, "response_type": "code", "redirect_uri": redirect,
            "scope": os.getenv("FEISHU_SCOPES", SCOPES), "state": state,
            "code_challenge": challenge, "code_challenge_method": "S256", "prompt": "consent"})
        return {"session_token": bearer, "authorization_url": url, "expires_in": 8 * 3600}

    @app.get("/oauth/feishu/callback", response_class=HTMLResponse)
    async def callback(state: str = "", code: str = "", error: str = ""):
        ready()
        pending = vault.consume_state(state)
        if not pending:
            raise HTTPException(400, {"message": "OAuth state 无效、已使用或已过期，请重新发起授权"})
        session_key, verifier = pending
        if error or not code:
            vault.fail(session_key, "用户取消或拒绝授权")
            return HTMLResponse("<h2>授权未完成</h2><p>请返回智学帮重新连接。</p>", status_code=400)
        try:
            tokens = await api.exchange(grant_type="authorization_code", code=code,
                                        redirect_uri=redirect, code_verifier=verifier)
            vault.save_tokens(session_key, tokens)
            user = await api.request(session_key, "GET", "/authen/v1/user_info")
            if not user.get("open_id"):
                raise HTTPException(502, {"message": "飞书未返回用户身份"})
            account = str(user.get("tenant_key", "")) + ":" + user["open_id"]
            vault.save_tokens(session_key, tokens, account)
        except HTTPException as failure:
            detail = failure.detail if isinstance(failure.detail, dict) else {}
            code = detail.get("feishu_code")
            message = detail.get("message", "授权交换失败，请返回 App 重新连接")
            vault.fail(session_key, message + (f"（错误码 {code}）" if code else ""))
            return HTMLResponse("<meta name='viewport' content='width=device-width,initial-scale=1'>"
                                "<h2>飞书授权未完成</h2><p>" + escape(message) + "</p>"
                                + (f"<p>飞书错误码：{int(code)}</p>" if isinstance(code, int) else "")
                                + "<p>请返回智学帮重新连接，无需重复开通权限。</p>", status_code=failure.status_code)
        return "<h2>飞书授权成功</h2><p>请返回智学帮，连接状态会自动更新。此页面不会显示 Token。</p>"

    @app.get("/connection")
    async def connection(session_key: str = Depends(session)):
        row = vault.get(session_key)
        if row["status"] == "connected":
            await api.access_token(session_key)
            row = vault.get(session_key)
        tokens = vault.tokens(row) if row["tokens"] else {}
        expired = row["status"] == "pending" and row["state_expires"] < time.time()
        return {"status": "failed" if expired else row["status"], "account_id": row["account"],
                "connection_id": session_key, "tenant_id": row["account"].split(":")[0] if row["account"] else None,
                "error": "授权请求已过期，请重新连接" if expired else row["error"],
                "scopes": tokens.get("scope", "").split(), "can_refresh": bool(tokens.get("refresh_token"))}

    @app.delete("/connection")
    async def disconnect(session_key: str = Depends(session)):
        vault.delete(session_key)
        api.locks.pop(session_key, None)
        return {"disconnected": True}

    @app.get("/folders/{folder_token}")
    async def folder(folder_token: str, session_key: str = Depends(session)):
        return await api.folder(session_key, folder_token)

    @app.get("/files")
    async def files(folder_token: str = "", session_key: str = Depends(session)):
        return {"items": await api.files(session_key, folder_token)}

    @app.get("/wiki/spaces")
    async def spaces(session_key: str = Depends(session)):
        return {"items": await api.pages(session_key, "/wiki/v2/spaces", "items", page_size=50)}

    @app.get("/wiki/spaces/{space_id}/nodes")
    async def nodes(space_id: str, parent_node_token: str = "", session_key: str = Depends(session)):
        if not space_id.isdigit():
            raise HTTPException(422, {"message": "知识空间 ID 无效"})
        return {"items": await api.pages(session_key, f"/wiki/v2/spaces/{space_id}/nodes", "items",
                                        page_size=50, parent_node_token=parent_node_token)}

    class ImportSelection(BaseModel):
        container_type: str
        container_id: str
        document_ids: list[str]

    @app.post("/imports/read")
    async def read(selection: ImportSelection, session_key: str = Depends(session)):
        # Titles, timestamps and membership always come from upstream, never the client.
        if selection.container_type == "folder":
            meta = await api.folder(session_key, selection.container_id)
            title = meta["name"]
            entries = await api.files(session_key, selection.container_id)
        elif selection.container_type == "wiki" and selection.container_id.isdigit():
            meta = await api.request(session_key, "GET", f"/wiki/v2/spaces/{selection.container_id}")
            title = meta["space"]["name"]
            entries, pending, visited = [], [""], set()
            while pending:
                parent = pending.pop()
                if parent in visited:
                    continue
                visited.add(parent)
                children = await api.pages(session_key, f"/wiki/v2/spaces/{selection.container_id}/nodes", "items",
                                           page_size=50, parent_node_token=parent)
                for node in children:
                    entries.append({"token": node["obj_token"], "type": node["obj_type"],
                                    "modified_time": node.get("obj_edit_time"), "node_token": node["node_token"]})
                    if node.get("has_child"):
                        pending.append(node["node_token"])
        else:
            raise HTTPException(422, {"message": "仅支持文件夹或知识空间"})
        supported = {f["token"]: f for f in entries if f["type"] == "docx"}
        ids = list(dict.fromkeys(selection.document_ids))
        if not ids or any(not re.fullmatch(r"[A-Za-z0-9]+", doc) or doc not in supported for doc in ids):
            raise HTTPException(422, {"message": "请选择此容器中有权访问的新版 docx"})
        documents, failures = [], []
        for doc in ids:
            try:
                document = await api.document(session_key, doc)
                document.update({"modified_time": supported[doc].get("modified_time"),
                                 "node_token": supported[doc].get("node_token"),
                                 "source_url": supported[doc].get("url") or "https://feishu.cn/wiki/" + supported[doc].get("node_token", doc)})
                documents.append(document)
            except HTTPException as failure:
                failures.append({"document_id": doc, "status": failure.status_code, "detail": failure.detail})
        return {"account_id": vault.get(session_key)["account"], "container_type": selection.container_type,
                "container_id": selection.container_id, "container_name": title,
                "documents": documents, "failures": failures}

    register_resources(app, api, vault, session)
    return app


app = create_app()
