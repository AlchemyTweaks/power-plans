# Import-AllPlans.ps1
# Imports every .pow power plan in the plans\ folder into Windows Power Options
# (Control Panel > Hardware and Sound > Power Options), in one pass.
# Each plan is imported under a fresh GUID, so existing plans are never overwritten.

# --- Self-elevate to Administrator if not already ---
$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process -FilePath 'powershell.exe' -Verb RunAs `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

$ErrorActionPreference = 'Continue'
$plansDir = Join-Path $PSScriptRoot 'plans'

if (-not (Test-Path -LiteralPath $plansDir)) {
    Write-Host "plans folder not found next to this script:" -ForegroundColor Red
    Write-Host "  $plansDir"
    Read-Host 'Press Enter to exit'
    exit 1
}

$files = Get-ChildItem -LiteralPath $plansDir -Filter '*.pow' -File
if ($files.Count -eq 0) {
    Write-Host "No .pow files found in $plansDir" -ForegroundColor Yellow
    Read-Host 'Press Enter to exit'
    exit 1
}

Write-Host "Importing $($files.Count) power plans into Windows Power Options..." -ForegroundColor Cyan
Write-Host ""

$ok = 0
$fail = 0
foreach ($file in $files) {
    $guid = [guid]::NewGuid().ToString()
    powercfg /import "$($file.FullName)" $guid > $null 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host ("  [OK]   {0}" -f $file.Name) -ForegroundColor Green
        $ok++
    } else {
        Write-Host ("  [FAIL] {0}" -f $file.Name) -ForegroundColor Red
        $fail++
    }
}

Write-Host ""
Write-Host ("Done. Imported {0} of {1} ({2} failed)." -f $ok, $files.Count, $fail) -ForegroundColor Cyan
Write-Host "Open Power Options to see them all:"
Write-Host "  control /name Microsoft.PowerOptions   (or run: powercfg.cpl)"
Write-Host ""
Write-Host "Note: running this script again creates duplicate copies of every plan." -ForegroundColor DarkYellow
Read-Host 'Press Enter to exit'
