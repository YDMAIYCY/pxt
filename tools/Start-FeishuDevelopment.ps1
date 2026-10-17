param(
    [string]$DeviceId,
    [string]$AdbPath = 'D:\Android\Sdk\platform-tools\adb.exe'
)

$ErrorActionPreference = 'Stop'
$connectorRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'services\feishu_connector'

function Get-ConnectorHealth {
    try {
        return Invoke-RestMethod -Uri 'http://127.0.0.1:8787/health' -TimeoutSec 2
    } catch {
        return $null
    }
}

$health = Get-ConnectorHealth
if ($null -eq $health) {
    $pythonPath = Join-Path $connectorRoot '.venv\Scripts\python.exe'
    if (-not (Test-Path -LiteralPath $pythonPath)) {
        throw 'Feishu connector Python environment is missing. Set up services/feishu_connector/.venv first.'
    }
    $logRoot = Join-Path $connectorRoot 'data'
    New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    Start-Process -FilePath $pythonPath `
        -ArgumentList @('-m', 'uvicorn', 'main:app', '--host', '127.0.0.1', '--port', '8787', '--workers', '1', '--no-access-log') `
        -WorkingDirectory $connectorRoot -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $logRoot "service-$stamp.out.log") `
        -RedirectStandardError (Join-Path $logRoot "service-$stamp.err.log") | Out-Null
    for ($attempt = 0; $attempt -lt 20; $attempt++) {
        Start-Sleep -Milliseconds 250
        $health = Get-ConnectorHealth
        if ($null -ne $health) { break }
    }
}
if ($null -eq $health) {
    throw 'Feishu connector did not start. Check services/feishu_connector/data/service-*.err.log and port 8787.'
}
if ($health.ready -ne $true) {
    throw ('Fill in services/feishu_connector/.env. Missing settings: ' + ($health.missing -join ', '))
}
Write-Output 'Feishu connector: ready (127.0.0.1:8787).'

if (-not (Test-Path -LiteralPath $AdbPath)) {
    throw 'ADB was not found. Supply -AdbPath with the Android SDK platform-tools/adb.exe path.'
}
$listing = & $AdbPath devices
if ($LASTEXITCODE -ne 0) { throw 'Unable to list Android devices.' }
$devices = @($listing | ForEach-Object {
    if ($_ -match '^(\S+)\s+device\s*$') { $Matches[1] }
})
if (-not $DeviceId) {
    if ($devices.Count -ne 1) {
        throw 'Connect one USB-debugging device, or supply -DeviceId when multiple devices are connected.'
    }
    $DeviceId = $devices[0]
}
if ($DeviceId -notin $devices) { throw 'The selected Android device is not connected or has not authorized USB debugging.' }
& $AdbPath -s $DeviceId reverse tcp:8787 tcp:8787
if ($LASTEXITCODE -ne 0) { throw 'Failed to restore the Android reverse port.' }
Write-Output "Android bridge: ready ($DeviceId, tcp:8787). Return to the App and connect your Feishu account."
