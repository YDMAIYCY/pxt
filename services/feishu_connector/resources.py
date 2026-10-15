"""Live resource normalization and recursive import planning; no fixture fallback."""
from urllib.parse import quote
from fastapi import Depends, HTTPException
from pydantic import BaseModel, Field


def resource(item: dict, account: str, parent: str | None, space: str = ""):
    if space:
        kind = item.get("obj_type", "wiki_node")
        token = item["node_token"]
        document = item.get("obj_token") if kind == "docx" else None
    else:
        kind = item.get("type", "wiki")
        token = item.get("token") or item.get("space_id")
        document = token if kind == "docx" else None
    return {"key": f"{kind}:{token}", "id": token, "account_id": account,
            "kind": kind, "name": item.get("name") or item.get("title") or "未命名",
            "parent_key": parent, "space_id": space or (token if kind == "wiki" else ""),
            "document_id": document, "has_children": kind in {"folder", "wiki"} or bool(item.get("has_child")),
            "supported": kind in {"docx", "folder", "wiki", "wiki_node"},
            "url": item.get("url"), "modified_time": item.get("modified_time") or item.get("obj_edit_time")}


class RootSelection(BaseModel):
    kind: str
    id: str
    space_id: str = ""
    excluded: list[str] = Field(default_factory=list)
    included: list[str] = Field(default_factory=list)
    document_ids: list[str] | None = None


class ScanRequest(BaseModel):
    roots: list[RootSelection]


def register_resources(app, api, vault, session):
    async def normalize(entry, account, parent, space="", key=""):
        if not space and entry.get("type") == "wiki":
            try:
                node = (await api.request(key, "GET", "/wiki/v2/spaces/get_node",
                                          params={"token": entry["token"]}))["node"]
                result = resource(node, account, parent, str(node["space_id"]))
                # A drive shortcut imports its linked document, not the entire Wiki branch.
                result["has_children"] = False
                return result
            except HTTPException as failure:
                if failure.status_code == 401:
                    raise
                return {**resource(entry, account, parent), "kind": "wiki_link",
                        "has_children": False, "supported": False,
                        "accessible": False, "error": failure.detail["message"]}
        return resource(entry, account, parent, space)

    @app.get("/resources")
    async def list_resources(kind: str = "drive", parent_id: str = "", parent_key: str | None = None,
                             space_id: str = "", page_token: str = "", key: str = Depends(session)):
        params = {"page_size": 50}
        if page_token:
            params["page_token"] = page_token
        if kind == "drive":
            params["folder_token"] = parent_id
            data = await api.request(key, "GET", "/drive/v1/files", params=params)
            entries = data.get("files", [])
        elif kind == "wiki" and not space_id:
            data = await api.request(key, "GET", "/wiki/v2/spaces", params=params)
            entries = data.get("items", [])
        elif kind == "wiki" and space_id.isdigit():
            params["parent_node_token"] = parent_id
            data = await api.request(key, "GET", f"/wiki/v2/spaces/{space_id}/nodes", params=params)
            entries = data.get("items", [])
        else:
            raise HTTPException(422, {"message": "资源类型或知识空间 ID 无效"})
        account = vault.get(key)["account"]
        if data.get("has_more") and (not data.get("page_token") or data.get("page_token") == page_token):
            raise HTTPException(502, {"message": "飞书分页标识异常，请重试"})
        return {"account_id": account, "items": [await normalize(e, account, parent_key, space_id, key) for e in entries],
                "has_more": data.get("has_more", False), "page_token": data.get("page_token")}

    @app.get("/documents/{document_id}")
    async def read_document(document_id: str, key: str = Depends(session)):
        return await api.document(key, document_id)

    @app.post("/imports/scan")
    async def scan(selection: ScanRequest, key: str = Depends(session)):
        # Verify provider identity before returning a plan; a local user ID is not authorization.
        await api.access_token(key)
        account = vault.get(key)["account"]
        roots, errors = [], []
        for selected in selection.roots:
            documents, descendants, unsupported = {}, set(), 0
            excluded = set(selected.excluded)
            included = set(selected.included)
            async def walk(folder: str, path: list[str], ancestors: list[str], wiki=False, blocked=False):
                nonlocal unsupported
                try:
                    if wiki:
                        entries = await api.pages(key, f"/wiki/v2/spaces/{selected.id}/nodes", "items",
                                                  page_size=50, parent_node_token=folder)
                    else:
                        entries = await api.files(key, folder)
                except HTTPException as failure:
                    if failure.status_code == 401:
                        raise
                    errors.append({"root_id": selected.id, "resource_id": folder,
                                   "path": "/".join(path), "status": failure.status_code, "detail": failure.detail})
                    return
                for entry in entries:
                    node = await normalize(entry, account, None, selected.id if wiki else "", key)
                    identity = node["key"]
                    hidden = blocked or identity in excluded
                    if identity in included:
                        hidden = False
                    if hidden and not included:
                        continue
                    title = node["name"]
                    if node["kind"] == "docx" and not hidden:
                        token = node["document_id"]
                        if selected.document_ids is None or token in selected.document_ids:
                            documents[token] = {"document_id": token, "title": title,
                                                "node_token": node["id"] if node["space_id"] else None,
                                                "relative_path": "/".join([*path, title]),
                                                "modified_time": node["modified_time"],
                                                "source_url": node["url"] or ("https://feishu.cn/wiki/" + node["id"] if node["space_id"] else "https://feishu.cn/docx/" + token)}
                    elif not node["supported"] and not hidden:
                        unsupported += 1
                    if node["has_children"]:
                        if identity in ancestors:
                            errors.append({"root_id": selected.id, "resource_id": node["id"], "detail": {"message": "资源树循环，已停止该分支"}})
                            continue
                        if not hidden:
                            descendants.add(identity)
                        await walk(node["id"], [*path, title], [*ancestors, identity], wiki,
                                   (blocked or identity in excluded) if node['kind'] == 'docx' else hidden)
            try:
                if selected.kind == "folder":
                    title = (await api.folder(key, selected.id))["name"]
                    await walk(selected.id, [], [f"folder:{selected.id}"])
                elif selected.kind == "wiki" and selected.id.isdigit():
                    title = (await api.request(key, "GET", f"/wiki/v2/spaces/{selected.id}"))["space"]["name"]
                    await walk("", [], [f"wiki:{selected.id}"], True)
                elif selected.kind == "docx":
                    token = selected.id
                    node_token = None
                    node_path = []
                    if selected.space_id:
                        node = (await api.request(key, "GET", "/wiki/v2/spaces/get_node", params={"token": selected.id}))["node"]
                        if node["obj_type"] != "docx":
                            raise HTTPException(422, {"message": "该 Wiki 节点不是新版云文档"})
                        if str(node.get("space_id")) != selected.space_id:
                            raise HTTPException(422, {"message": "Wiki 节点与所选知识空间不一致"})
                        token, node_token = node["obj_token"], node["node_token"]
                        parent = node.get("parent_node_token")
                        seen = {node_token}
                        while parent:
                            if parent in seen:
                                raise HTTPException(502, {"message": "Wiki 节点路径存在循环"})
                            seen.add(parent)
                            ancestor = (await api.request(key, "GET", "/wiki/v2/spaces/get_node",
                                                          params={"token": parent}))["node"]
                            node_path.insert(0, ancestor.get("title") or "未命名")
                            parent = ancestor.get("parent_node_token")
                    meta = (await api.request(key, "GET", "/docx/v1/documents/" + quote(token, safe="")))["document"]
                    title = meta["title"]
                    documents[token] = {"document_id": token, "title": title, "relative_path": "/".join([*node_path, title]), "node_token": node_token,
                                         "source_url": "https://feishu.cn/" + ("wiki/" + node_token if node_token else "docx/" + token)}
                else:
                    raise HTTPException(422, {"message": "请选择文件夹、新版云文档或整个知识空间"})
                roots.append({"kind": selected.kind, "id": selected.id, "name": title,
                              "space_id": selected.space_id, "excluded": selected.excluded,
                              "included": selected.included,
                              "documents": list(documents.values()), "descendants": list(descendants), "unsupported": unsupported})
            except HTTPException as failure:
                if failure.status_code == 401:
                    raise
                errors.append({"root_id": selected.id, "status": failure.status_code, "detail": failure.detail})
        # Parent coverage suppresses separately selected descendants and loose docs within that coverage.
        covered, result = [], []
        for root in roots:
            identity = f"{root['kind']}:{root['id']}"
            document_ids = {d["document_id"] for d in root["documents"]}
            if any((identity in other["descendants"] and document_ids.issubset({d["document_id"] for d in other["documents"]})) or
                   (root["kind"] == "docx" and document_ids.issubset({d["document_id"] for d in other["documents"]}))
                   for other in roots if other is not root and other["kind"] != "docx"):
                covered.append(identity)
            else:
                result.append(root)
        unique_loose, seen_docs = [], set()
        for root in result:
            doc_ids = {d["document_id"] for d in root["documents"]}
            if root["kind"] == "docx" and doc_ids.issubset(seen_docs):
                covered.append(f"docx:{root['id']}")
                continue
            if root["kind"] == "docx":
                seen_docs.update(doc_ids)
            unique_loose.append(root)
        return {"account_id": account, "roots": unique_loose, "errors": errors,
                "covered_selections": covered, "scan_complete": not errors,
                "content_access_checked": False}
