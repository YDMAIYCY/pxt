param([ValidateSet('debug','release')][string]$Mode = 'debug')
$ErrorActionPreference = 'Stop'
$cloudBuildRoot = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $cloudBuildRoot
try {
  & (Join-Path $PSScriptRoot 'Prepare-CloudConfig.ps1')
  & flutter build apk "--$Mode"
  if ($LASTEXITCODE -ne 0) { throw 'APK 构建失败。' }
  $cloudApkPath = Join-Path $cloudBuildRoot "build/app/outputs/flutter-apk/app-$Mode.apk"
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $cloudApkArchive = [IO.Compression.ZipFile]::OpenRead($cloudApkPath)
  try {
    $cloudEntry = $cloudApkArchive.GetEntry('assets/flutter_assets/assets/config/supabase.public.json')
    if ($null -eq $cloudEntry) { throw '安装包没有包含云服务公开配置，停止交付。' }
    $cloudReader = [IO.StreamReader]::new($cloudEntry.Open())
    try { $cloudPackaged = $cloudReader.ReadToEnd() | ConvertFrom-Json } finally { $cloudReader.Dispose() }
    $cloudExpected = Get-Content -LiteralPath config/supabase.local.json -Raw | ConvertFrom-Json
    if ($cloudPackaged.SUPABASE_URL -ne $cloudExpected.SUPABASE_URL.TrimEnd('/') -or $cloudPackaged.SUPABASE_PUBLISHABLE_KEY -ne $cloudExpected.SUPABASE_PUBLISHABLE_KEY) { throw '安装包的云服务配置与本地项目不一致。' }
  } finally { $cloudApkArchive.Dispose() }
  Write-Output 'APK 构建完成，已核对包内云服务配置。'
} finally { Pop-Location }
