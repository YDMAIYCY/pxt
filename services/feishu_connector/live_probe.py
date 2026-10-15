"""Run manually after configuring .env and publishing user scopes. No mock path."""
import argparse
import json
import time
import sys
import webbrowser
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlparse

import httpx

ROOT = Path(__file__).resolve().parent
DEFAULT_FOLDER = "https://bcn6zp64a7v4.feishu.cn/drive/folder/E283fXn4ElWJwTdOqNJcHxpinPd"


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser()
    parser.add_argument("--folder-url", default=DEFAULT_FOLDER)
    args = parser.parse_args()
    folder = urlparse(args.folder_url)
    if folder.scheme != "https" or not folder.hostname or not folder.hostname.endswith(".feishu.cn") or not folder.path.startswith("/drive/folder/"):
        raise SystemExit("请提供真实飞书文件夹 URL")
    token = folder.path.rstrip("/").split("/")[-1]
    report = {"checked_at": datetime.now(timezone.utc).isoformat(), "folder_id": token,
              "live_success": False, "steps": []}
    output = ROOT / "data"
    output.mkdir(exist_ok=True)
    headers = {}
    client = httpx.Client(base_url="http://127.0.0.1:8787", timeout=300)

    def request(method, path, **kwargs):
        response = client.request(method, path, headers=headers, **kwargs)
        report["steps"].append({"endpoint": path, "http_status": response.status_code})
        if response.is_error:
            report["error"] = response.json().get("detail")
            raise RuntimeError(f"连接服务返回 HTTP {response.status_code}")
        return response.json()

    try:
        health = request("GET", "/health")
        if not health["ready"]:
            report["missing"] = health["missing"]
            raise RuntimeError("后端配置不完整；未调用飞书 API")
        started = request("POST", "/oauth/feishu/start")
        headers["Authorization"] = "Bearer " + started["session_token"]
        webbrowser.open(started["authorization_url"])
        print("请在浏览器中完成飞书用户授权。本程序不会输出或保存客户端会话 Token。")
        for _ in range(100):
            connection = client.get("/connection", headers=headers).json()
            if connection.get("status") == "connected":
                report["granted_scopes"] = connection["scopes"]
                break
            if connection.get("status") == "failed":
                raise RuntimeError(connection["error"])
            time.sleep(3)
        else:
            raise RuntimeError("用户授权未在五分钟内完成")
        folder_info = request("GET", f"/folders/{token}")
        files = request("GET", "/files", params={"folder_token": token})["items"]
        docs = [file for file in files if file["type"] == "docx"]
        report.update({"folder_name": folder_info["name"], "listed_count": len(files), "supported_docx_count": len(docs)})
        if not docs:
            raise RuntimeError("文件夹当前层级没有受支持的 docx")
        payload = request("POST", "/imports/read", json={"container_type": "folder", "container_id": token,
                                                                  "document_ids": [docs[0]["token"]]})
        if not payload["documents"]:
            report["document_failures"] = payload["failures"]
            raise RuntimeError("未能读取 docx 正文")
        # Private content stays in ignored local data/. SQLite verification runs in Flutter.
        (output / "live_payload.json").write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
        report["live_success"] = True
        report["local_sqlite_verified"] = False
        report["document_id"] = payload["documents"][0]["document_id"]
        report["block_count"] = len(payload["documents"][0]["blocks"])
        report["text_length"] = len(payload["documents"][0]["text"])
    except (httpx.HTTPError, RuntimeError) as error:
        report["blocker"] = str(error)
    finally:
        if headers:
            try:
                client.delete("/connection", headers=headers)
            except httpx.HTTPError:
                pass
        client.close()
        (output / "live_report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if report["live_success"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
