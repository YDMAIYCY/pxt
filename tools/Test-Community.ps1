param([switch]$Live, [switch]$Screenshots)
$ErrorActionPreference = 'Stop'
$communityRoot = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $communityRoot
try {
  if ($Live) {
    if (-not (Test-Path -LiteralPath 'config/community-test.local.json')) {
      throw 'Copy config/community-test.example.json to config/community-test.local.json and fill two dedicated verified accounts.'
    }
    & flutter test test/community_live_test.dart --dart-define-from-file=config/supabase.local.json --dart-define-from-file=config/community-test.local.json --reporter expanded
    if ($LASTEXITCODE -ne 0) { throw 'Live two-user checks failed. See the sanitized test output.' }
  } else {
    & npm ci --prefix tools/community-db-check --cache .dart_tool/community-npm-cache --no-audit --no-fund
    if ($LASTEXITCODE -ne 0) { throw 'PostgreSQL test dependency installation failed.' }
    & node tools/community-db-check/check.mjs
    if ($LASTEXITCODE -ne 0) { throw 'PostgreSQL permission checks failed.' }
    $communityFlutterArgs = @('test', 'test/cloud_configuration_test.dart', 'test/community_identity_test.dart', 'test/community_ui_test.dart', 'test/community_navigation_test.dart', 'test/community_live_test.dart', 'test/unified_login_ui_test.dart', 'test/focus_repository_test.dart', 'test/focus_tab_layout_test.dart', 'test/tab_refresh_integration_test.dart', 'test/learning_ui_routing_test.dart', 'test/favorites_page_test.dart', 'test/feishu_import_test.dart', 'test/ocr_pipeline_service_test.dart', 'test/knowledge_hierarchy_data_test.dart', 'test/eclaw_agent_test.dart', 'test/llm_config_repository_test.dart', '--concurrency=1', '--reporter=expanded')
    if ($Screenshots) { $communityFlutterArgs += '--dart-define=UPDATE_COMMUNITY_SCREENSHOTS=true' }
    & flutter @communityFlutterArgs
    if ($LASTEXITCODE -ne 0) { throw 'Flutter community/local-data regression checks failed.' }
  }
} finally { Pop-Location }
