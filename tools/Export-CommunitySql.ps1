$ErrorActionPreference = 'Stop'
$communitySqlRoot = Split-Path -Parent $PSScriptRoot
$communityOutputDirectory = Join-Path $communitySqlRoot '.dart_tool'
[IO.Directory]::CreateDirectory($communityOutputDirectory) | Out-Null
$communitySqlFiles = Get-ChildItem -LiteralPath (Join-Path $communitySqlRoot 'supabase/migrations') -Filter '*.sql' | Sort-Object Name
$communitySqlParts = @('-- For an EMPTY community schema only. Already deployed 001? Apply only migration 002 instead.')
foreach ($communitySqlFile in $communitySqlFiles) {
  $communitySqlParts += "-- Migration: $($communitySqlFile.Name)"
  $communitySqlParts += [IO.File]::ReadAllText($communitySqlFile.FullName)
}
$communitySqlOutput = Join-Path $communityOutputDirectory 'community-deploy.sql'
[IO.File]::WriteAllText($communitySqlOutput, ($communitySqlParts -join "`n`n"), [Text.UTF8Encoding]::new($false))
Write-Output '已从版本化迁移生成 .dart_tool/community-deploy.sql；此脚本没有执行任何远端操作。'
