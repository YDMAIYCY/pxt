$ErrorActionPreference = 'Stop'
$cloudProjectRoot = Split-Path -Parent $PSScriptRoot
$cloudConfigPath = Join-Path $cloudProjectRoot 'config/supabase.local.json'
if (-not (Test-Path -LiteralPath $cloudConfigPath)) { throw '缺少 config/supabase.local.json，请按无密钥模板填写项目公开配置。' }
try { $cloudValues = Get-Content -LiteralPath $cloudConfigPath -Raw | ConvertFrom-Json }
catch { throw '云服务本地配置不是有效 JSON。' }
$cloudUrl = [string]$cloudValues.SUPABASE_URL
$cloudKey = [string]$cloudValues.SUPABASE_PUBLISHABLE_KEY
$cloudUri = $null
if (-not [Uri]::TryCreate($cloudUrl, [UriKind]::Absolute, [ref]$cloudUri) -or $cloudUri.Scheme -ne 'https' -or $cloudUri.UserInfo -or $cloudUri.Query -or $cloudUri.Fragment -or $cloudUri.AbsolutePath -ne '/') {
  throw '请填写 Supabase API HTTPS 根地址，不是 dashboard 控制台链接。'
}
if (-not $cloudKey.StartsWith('sb_publishable_')) { throw '客户端配置只允许 Publishable Key，禁止放入服务端密钥。' }
$cloudAssetDirectory = Join-Path $cloudProjectRoot 'assets/config'
[IO.Directory]::CreateDirectory($cloudAssetDirectory) | Out-Null
$cloudPublicValues = @{ SUPABASE_URL = $cloudUrl.TrimEnd('/'); SUPABASE_PUBLISHABLE_KEY = $cloudKey }
$cloudPublicJson = $cloudPublicValues | ConvertTo-Json
[IO.File]::WriteAllText((Join-Path $cloudAssetDirectory 'supabase.public.json'), $cloudPublicJson, [Text.UTF8Encoding]::new($false))
Write-Output '云服务公开配置已准备；未包含服务端密钥。'
