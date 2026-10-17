$ErrorActionPreference = 'Stop'
$communityProjectRoot = Split-Path -Parent $PSScriptRoot
try {
  $communityConfig = Get-Content -LiteralPath (Join-Path $communityProjectRoot 'config/supabase.local.json') -Raw | ConvertFrom-Json
} catch { throw '无法读取本地公开配置，请先配置 config/supabase.local.json。' }
$communityHeaders = @{ apikey = [string]$communityConfig.SUPABASE_PUBLISHABLE_KEY }
$communityMissing = $false
foreach ($communityEndpoint in @('/auth/v1/settings', '/rest/v1/profiles?select=id&limit=1', '/rest/v1/community_questions?select=id&limit=1')) {
  $communityResponse = $null
  try {
    $communityResponse = Invoke-WebRequest -UseBasicParsing -Uri ($communityConfig.SUPABASE_URL.TrimEnd('/') + $communityEndpoint) -Headers $communityHeaders -TimeoutSec 20
    $communityStatus = [int]$communityResponse.StatusCode
  } catch {
    if ($null -eq $_.Exception.Response) { throw '无法连接项目，请检查网络及配置；未输出请求凭据。' }
    $communityStatus = [int]$_.Exception.Response.StatusCode
  }
  if ($communityEndpoint -eq '/auth/v1/settings') {
    if ($communityStatus -ne 200) { throw '认证服务不可用，请检查项目 URL 和 Publishable Key。' }
    $communitySettings = $communityResponse.Content | ConvertFrom-Json
    if ($communitySettings.mailer_autoconfirm) { Write-Output '认证服务可用；新注册账号无需邮件确认。' }
    else { Write-Output '认证服务可用；当前新注册账号必须完成邮箱确认。' }
  } elseif ($communityStatus -eq 404) {
    $communityMissing = $true
    Write-Output ('尚未识别社区结构：' + $communityEndpoint.Split('?')[0])
  } elseif ($communityStatus -in @(200, 401, 403)) {
    Write-Output ('已识别数据接口：' + $communityEndpoint.Split('?')[0] + '；具体访问权限需用登录账号验收。')
  } else { throw '数据接口返回异常，请检查远端部署；未输出请求凭据。' }
}
if ($communityMissing) { Write-Output '数据 API 尚未识别社区结构；请核对 SQL 部署结果及接口缓存，再运行双账号验收。'; exit 2 }
Write-Output '只读预检完成；这不等于双用户、Storage 或 Realtime 已验证。'
