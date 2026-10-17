"""Deploy the learning-community migrations to project epbbtiustevdyjcjgepj.

The project owner supplies a Supabase personal access token through the
SUPABASE_ACCESS_TOKEN environment variable. The token is read from memory only
and is never written to disk, never printed, and never logged.

Usage (PowerShell):
  $env:SUPABASE_ACCESS_TOKEN = 'sbp_...'
  python tools/deploy_community_cloud.py

Usage (bash):
  SUPABASE_ACCESS_TOKEN=sbp_... python tools/deploy_community_cloud.py
"""

import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

PROJECT_REF = "epbbtiustevdyjcjgepj"
ENDPOINT = "https://api.supabase.com/v1/projects/{ref}/database/query"
ROOT = Path(__file__).resolve().parents[1]
DEPLOY_SQL = ROOT / ".dart_tool" / "community-deploy.sql"
CHECK_SQL = ROOT / ".dart_tool" / "community-deployment-check.sql"


def run(token, sql):
    request = urllib.request.Request(
        ENDPOINT.format(ref=PROJECT_REF),
        data=json.dumps({"query": sql}).encode("utf-8"),
        headers={
            "Authorization": "Bearer " + token,
            "Content-Type": "application/json",
            "User-Agent": "pxt-community-deploy/1",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=180) as response:
            return response.status, response.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as error:
        return error.code, error.read().decode("utf-8", "replace")
    except OSError as error:
        return 0, "无法连接 Supabase 接口：%s" % error


def main():
    token = os.environ.get("SUPABASE_ACCESS_TOKEN", "").strip()
    if not token.startswith("sbp_"):
        print("缺少 SUPABASE_ACCESS_TOKEN（应以 sbp_ 开头）。令牌不会被写入磁盘。")
        return 2
    for path in (DEPLOY_SQL, CHECK_SQL):
        if not path.exists():
            print("缺少文件：%s" % path)
            return 2

    print("== 1/2 执行迁移到 %s ==" % PROJECT_REF)
    status, body = run(token, DEPLOY_SQL.read_text(encoding="utf-8"))
    print("HTTP %s" % status)
    print(body[:600] if body.strip() else "(空响应 = 执行成功)")
    if status >= 300:
        return 1

    print()
    print("== 2/2 部署结果校验 ==")
    status, body = run(token, CHECK_SQL.read_text(encoding="utf-8"))
    print("HTTP %s" % status)
    print(body[:1200] if body.strip() else "(空响应)")
    return 0 if status < 300 else 1


if __name__ == "__main__":
    sys.exit(main())
