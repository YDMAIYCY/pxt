$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
& .\.venv\Scripts\python.exe -m uvicorn main:app --host 127.0.0.1 --port 8787 --workers 1 --no-access-log
