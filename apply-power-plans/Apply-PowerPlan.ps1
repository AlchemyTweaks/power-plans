# ============================================================
#  Power Plan Manager - Apply Script  (tested plans only)
#  Imports and activates a tested power plan (.pow) of your choice.
# ============================================================

# --- Auto-elevate to Administrator ---
$me = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Administrator rights required. Restarting as Administrator..." -ForegroundColor Yellow
    Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

$ErrorActionPreference = 'Stop'
$here     = Split-Path -Parent $MyInvocation.MyCommand.Definition
$plansDir = Join-Path $here 'plans'
$BAL_GUID = '381b4222-f694-41f0-9685-ff5bb260df2e'  # Windows Balanced

# Map .pow filename (without extension) -> name as it appears in the FPS-analysis Excel
$ExcelName = @{
  'arsenza low latency (INTEL FIX THREAD-DIRECTOR)' = 'Arsenza-PowerPlan-INTEL'
  'Gavot Performance' = 'EndGame-PowerPlan'
  'Prodazin Power Plan' = 'Prodazin-PowerPlan'
  'Custom - Idle Enabled Low Latency Amit v3' = 'AMIT-PowerPlan'
  'LLG-CΞRT1F1ΞD-FOR-PARKING+E-CORES-FIX' = 'LLG-CERTIFIED-FOR-PARKING+E-CORES-FIX-PowerPlan'
  '0 Synez_Public_Power' = 'Synez-PowerPlan'
  'RevisionPowerPlanV2.8' = 'Revision-PowerPlan'
  'Reticle v2' = 'Reticle-PowerPlan'
  'LLG-C#U039eRT1F1#U039eD-FOR-NON-K-CPUs' = 'LLG-CERTIFIED-FOR-NON-K-CPUs-PowerPlan'
  'cactusOS' = 'CactusOS-PowerPlan'
  'imribiy2026' = 'Imribiy-2026-PowerPlan'
  'FPSHEAVEN2026' = 'FPSHEAVEN2026-PowerPlan'
  'Mitstas IDLE ENABLED' = 'Mitstas-PowerPlan'
  'Bitsum Highest Performance' = 'Bitsum-Highest-Performance-PowerPlan'
  'AutoOS' = 'AutoOS-PowerPlan'
  'RIP Tweaks Power Plan' = 'RIP-PowerPlan'
  'Slower' = 'Slower-PowerPlan'
  'BEYOND-PERFORMANCE-AMD+INTEL' = 'BEYOND-PERFORMANCE-AMD-INTEL-V1-PowerPlan'
  'IrisFixed' = 'Iris-PowerPlan'
  'SapphireOS' = 'Sapphire-PowerPlan'
  'KSOS11' = 'Sazinho-PowerPlan'
  'J o k r O S   P o w e r   P l a n' = 'JokrOS-PowerPlan'
  'Khorvie' = 'Khorvie-PowerPlan'
  'GALA''s ultimate performance(AMD)' = 'GALA''S-Ultimate-Performance-AMD-PowerPlan'
  'Jackpot2026' = 'Jackpot2026-PowerPlan'
  'arsenza low latency' = 'Arsezna-PowerPlan-ALL-CPU'
  'Rosca Tweaks v2' = 'RoscaV2-PowerPlan'
  'n1kobg GPU_Booster_Power_Plan' = 'GPU-BOOSTER-PowerPlan'
  'IIIEXOIII_LOW_LATENCY' = 'IIIEXOIII-PowerPlan'
  'HybredLowLatencyHighPerf' = 'Hybred-Low-Latency-PowerPlan'
  'Microsoft High performance' = 'MSFT-High-Performance-PowerPlan'
  'GTweaks Power Plan V3' = 'GTweaks-PowerPlan'
  'Kizzimo''s Extreme Low Latency' = 'Kizzimo-PowerPlan'
  'XNRL Pro Plan' = 'XNRL-PowerPlan'
  'Microsoft Ultimate Performance' = 'MSFT-UltimatePerformance-PowerPlan'
  'Xilly' = 'XILLY''S-PowerPlan'
  'melody LowestLatency' = 'LowLatency-PowerPlan'
  'VTRL Optimized' = 'VTRL-PowerPlan'
  'Velo''s Power Plan' = 'Velo''s-PowerPlan'
}

function Pause-Exit { Write-Host ''; Read-Host 'Press Enter to exit'; exit }

Clear-Host
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host '          POWER PLAN MANAGER  -  Apply Tool (tested)'        -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ''
Write-Host '  !!! WARNING !!!' -ForegroundColor Red
Write-Host '  Some of these power plans have caused a BLUE SCREEN (BSOD)' -ForegroundColor Red
Write-Host '  or instability on certain machines. Apply at your own risk.' -ForegroundColor Red
Write-Host '  It is recommended to create a System Restore Point first.' -ForegroundColor Yellow
Write-Host '  If the PC will not boot: Safe Mode -> select "Balanced" again.' -ForegroundColor Yellow
Write-Host ''

if (-not (Test-Path $plansDir)) { Write-Host "Folder not found: $plansDir" -ForegroundColor Red; Pause-Exit }
$files = Get-ChildItem -Path $plansDir -Filter *.pow | Sort-Object Name
if ($files.Count -eq 0) { Write-Host 'No .pow files found in the plans folder.' -ForegroundColor Red; Pause-Exit }

Write-Host '  Tested power plans (Excel name shown):' -ForegroundColor Green
for ($i=0; $i -lt $files.Count; $i++) {
    $base = $files[$i].BaseName
    $nm = if ($ExcelName.ContainsKey($base)) { $ExcelName[$base] } else { $base }
    '    [{0,2}] {1}' -f ($i+1), $nm | Write-Host
}
Write-Host ''
Write-Host '    [ R] Restore the default Windows "Balanced" plan' -ForegroundColor Cyan
Write-Host '    [ Q] Quit' -ForegroundColor Cyan
Write-Host ''

$choice = Read-Host 'Enter the plan number (or R / Q)'
if ($choice -match '^[Qq]$') { exit }
if ($choice -match '^[Rr]$') {
    powercfg /setactive $BAL_GUID
    Write-Host ''; Write-Host 'OK - Activated the Windows "Balanced" plan.' -ForegroundColor Green
    powercfg /getactivescheme; Pause-Exit
}
$n = 0
if (-not [int]::TryParse($choice,[ref]$n) -or $n -lt 1 -or $n -gt $files.Count) {
    Write-Host 'Invalid choice.' -ForegroundColor Red; Pause-Exit
}
$plan = $files[$n-1]
$planName = if ($ExcelName.ContainsKey($plan.BaseName)) { $ExcelName[$plan.BaseName] } else { $plan.BaseName }
Write-Host ''
Write-Host ("Selected: " + $planName + "   (" + $plan.Name + ")") -ForegroundColor Green

$rp = Read-Host 'Create a System Restore Point first? (y/n)'
if ($rp -match '^[Yy]') {
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description ("Before " + $planName) -RestorePointType MODIFY_SETTINGS
        Write-Host 'Restore point created.' -ForegroundColor Green
    } catch { Write-Host 'Could not create a restore point (System Protection may be disabled).' -ForegroundColor Yellow }
}

$ok = Read-Host 'Are you sure you want to APPLY this plan? (y/n)'
if ($ok -notmatch '^[Yy]') { Write-Host 'Cancelled.' -ForegroundColor Yellow; Pause-Exit }

$newGuid = [guid]::NewGuid().ToString()
Write-Host ''
Write-Host ('Importing: ' + $plan.Name) -ForegroundColor Cyan
powercfg /import "$($plan.FullName)" $newGuid
if ($LASTEXITCODE -ne 0) { Write-Host 'Import failed.' -ForegroundColor Red; Pause-Exit }
powercfg /setactive $newGuid
if ($LASTEXITCODE -ne 0) { Write-Host 'Activation failed.' -ForegroundColor Red; Pause-Exit }

Write-Host ''
Write-Host '============================================================' -ForegroundColor Green
Write-Host ('  ACTIVATED: ' + $planName) -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
powercfg /getactivescheme
Write-Host ''
Write-Host 'If the system becomes unstable: run again and press [R] to restore Balanced.' -ForegroundColor Yellow
Pause-Exit
