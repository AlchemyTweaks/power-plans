# ============================================================================
#  Alchemy Tweaks - Power Plan Tool  (v2)
#  One engine for: Apply (pick + activate), ImportAll, Diagnose, Cleanup.
#
#  Why v2: v1 called "powercfg /import" directly on the file inside the
#  downloaded folder and only trusted its exit code. On many systems that
#  path is a OneDrive / Files-On-Demand placeholder, a USB or network drive,
#  a ZIP preview folder, or contains non-ASCII characters, and the import
#  either fails or reports success without creating the scheme.
#
#  v2 safeguards:
#   1. Every .pow is read fully into memory and written to a local, ASCII-only
#      temp path before powercfg ever touches it (forces OneDrive hydration,
#      drops Mark-of-the-Web, avoids network/USB/Unicode path issues).
#   2. Each file is validated: "regf" hive signature + SHA-256 from
#      plans-manifest.json (detects truncated or corrupted downloads).
#   3. Import result is VERIFIED (scheme key exists / listed by powercfg),
#      not trusted from the exit code alone.
#   4. Three import strategies, tried in order:
#        A. powercfg /import <file> <stable GUID>
#        B. powercfg /import <file>            (GUID diff before/after)
#        C. Rebuild: load the .pow as a registry hive (read-only use),
#           duplicate a built-in base scheme and apply every setting with
#           powercfg /setacvalueindex + /setdcvalueindex.
#   5. Stable GUID per plan (derived from file hash): re-running never creates
#      duplicates; an already-installed plan is reused.
#   6. Activation is verified with /getactivescheme; Group Policy overrides
#      and Modern Standby systems are detected and reported.
#   7. Everything is logged to logs\ next to this script (or %TEMP%).
#
#  This file is intentionally ASCII-only (safe for Windows PowerShell 5.1
#  regardless of file encoding). Plan names live in plans-manifest.json.
# ============================================================================

param(
    [ValidateSet('Menu', 'Apply', 'ImportAll', 'Diagnose', 'Cleanup', 'Restore')]
    [string]$Mode = 'Menu',
    [switch]$NoPause
)

$ToolVersion = '2.0.0'
$ErrorActionPreference = 'Continue'
Set-StrictMode -Off

# ---------------------------------------------------------------------------
# Paths and constants
# ---------------------------------------------------------------------------
$ScriptDir    = Split-Path -Parent $MyInvocation.MyCommand.Definition
$PlansDir     = Join-Path $ScriptDir 'plans'
$ManifestPath = Join-Path $ScriptDir 'plans-manifest.json'

$GUID_BALANCED  = '381b4222-f694-41f0-9685-ff5bb260df2e'
$GUID_HIGHPERF  = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
$GUID_SAVER     = 'a1841308-3541-4fab-bc81-f71556f20b4a'
$GUID_ULTIMATE  = 'e9a42b02-d5df-448d-aa00-03f14749eb61'
$GUID_NO_SUBGRP = 'fea3413e-7e05-4911-9a71-700331f1c294'
$GUID_PERSONALITY = '245d8541-3943-4422-b025-13a784f679b7'
$BuiltInSchemes = @($GUID_BALANCED, $GUID_HIGHPERF, $GUID_SAVER, $GUID_ULTIMATE)

$GuidRx = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'

# 32-bit PowerShell on 64-bit Windows must call the native System32 tools.
$SysDir = Join-Path $env:SystemRoot 'System32'
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $SysDir = Join-Path $env:SystemRoot 'Sysnative'
}
$PowerCfg = Join-Path $SysDir 'powercfg.exe'
$RegExe   = Join-Path $SysDir 'reg.exe'

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
$script:LogFile = $null
function Initialize-Log {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $candidates = @((Join-Path $ScriptDir 'logs'), (Join-Path ([IO.Path]::GetTempPath()) 'AlchemyPowerPlans\logs'))
    foreach ($dir in $candidates) {
        try {
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null }
            $f = Join-Path $dir ("powerplans-$Mode-$stamp.log")
            [IO.File]::WriteAllText($f, "Alchemy Power Plan Tool v$ToolVersion  mode=$Mode  $(Get-Date -Format o)`r`n")
            $script:LogFile = $f
            return
        } catch { }
    }
}
function Write-Log {
    param([string]$Message, [string]$Level = 'INFO', [switch]$Quiet)
    $color = 'Gray'
    switch ($Level) { 'OK' { $color = 'Green' } 'WARN' { $color = 'Yellow' } 'ERROR' { $color = 'Red' } 'STEP' { $color = 'Cyan' } }
    if (-not $Quiet) { Write-Host $Message -ForegroundColor $color }
    if ($script:LogFile) {
        try { [IO.File]::AppendAllText($script:LogFile, ("[{0}] {1,-5} {2}`r`n" -f (Get-Date -Format 'HH:mm:ss'), $Level, $Message)) } catch { }
    }
}
function Exit-Tool {
    param([int]$Code = 0)
    if ($script:LogFile) { Write-Host ''; Write-Host "Log file: $script:LogFile" -ForegroundColor DarkGray }
    if (-not $NoPause) { Write-Host ''; Read-Host 'Press Enter to exit' | Out-Null }
    exit $Code
}

# ---------------------------------------------------------------------------
# Native command wrapper (never throws, always returns exit code + output)
# ---------------------------------------------------------------------------
function Invoke-Native {
    param([string]$Exe, [string[]]$Arguments)
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & $Exe @Arguments 2>&1 | ForEach-Object { "$_" }
        $code = $LASTEXITCODE
    } catch {
        $out = @("$_"); $code = -1
    } finally { $ErrorActionPreference = $old }
    $text = ($out -join "`n").Trim()
    Write-Log ("  > {0} {1}  [exit {2}]{3}" -f (Split-Path $Exe -Leaf), ($Arguments -join ' '), $code, $(if ($text) { "  $text" } else { '' })) -Level 'INFO' -Quiet
    return [pscustomobject]@{ ExitCode = $code; Output = $text }
}
function Invoke-PowerCfg { param([string[]]$Arguments) return Invoke-Native -Exe $PowerCfg -Arguments $Arguments }

# ---------------------------------------------------------------------------
# Elevation
# ---------------------------------------------------------------------------
function Test-IsAdmin {
    $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Request-Elevation {
    Write-Host 'Administrator rights required. Requesting elevation (UAC)...' -ForegroundColor Yellow
    $psExe = Join-Path $PSHOME 'powershell.exe'
    if (-not (Test-Path -LiteralPath $psExe)) { $psExe = 'powershell.exe' }
    $argLine = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Mode $Mode"
    if ($NoPause) { $argLine += ' -NoPause' }
    try {
        Start-Process -FilePath $psExe -ArgumentList $argLine -Verb RunAs -WorkingDirectory $ScriptDir -ErrorAction Stop | Out-Null
        exit 0
    } catch {
        Write-Host ''
        Write-Host 'Elevation was cancelled or blocked.' -ForegroundColor Red
        Write-Host 'Right-click the .bat file and choose "Run as administrator".' -ForegroundColor Yellow
        if (-not $NoPause) { Read-Host 'Press Enter to exit' | Out-Null }
        exit 5
    }
}

# ---------------------------------------------------------------------------
# Scheme queries (language independent: GUID regex + registry)
# ---------------------------------------------------------------------------
function Get-SchemeList {
    $r = Invoke-PowerCfg @('/list')
    $list = @()
    foreach ($line in ($r.Output -split "`n")) {
        $m = [regex]::Match($line, "($GuidRx)\s*\((.*)\)\s*(\*)?\s*$")
        if ($m.Success) {
            $list += [pscustomobject]@{ Guid = $m.Groups[1].Value.ToLower(); Name = $m.Groups[2].Value.Trim(); Active = ($m.Groups[3].Value -eq '*') }
        }
    }
    return ,$list
}
function Test-SchemeExists {
    param([string]$Guid)
    $g = $Guid.ToLower()
    if (Test-Path -LiteralPath "Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes\$g") { return $true }
    foreach ($s in (Get-SchemeList)) { if ($s.Guid -eq $g) { return $true } }
    return $false
}
function Get-ActiveSchemeGuid {
    $r = Invoke-PowerCfg @('/getactivescheme')
    $m = [regex]::Match($r.Output, $GuidRx)
    if ($m.Success) { return $m.Value.ToLower() }
    return $null
}

# ---------------------------------------------------------------------------
# Plan catalogue (manifest + files on disk)
# ---------------------------------------------------------------------------
function Get-StableGuid {
    param([byte[]]$Bytes)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $h = $sha.ComputeHash($Bytes) } finally { $sha.Dispose() }
    $b = New-Object byte[] 16
    [Array]::Copy($h, $b, 16)
    $b[7] = ($b[7] -band 0x0F) -bor 0x50
    $b[8] = ($b[8] -band 0x3F) -bor 0x80
    return (New-Object Guid (, $b)).ToString()
}
function Get-Sha256Hex {
    param([byte[]]$Bytes)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $h = $sha.ComputeHash($Bytes) } finally { $sha.Dispose() }
    return (($h | ForEach-Object { $_.ToString('x2') }) -join '')
}
function Get-PlanCatalog {
    $manifest = @{}
    if (Test-Path -LiteralPath $ManifestPath) {
        try {
            $json = [IO.File]::ReadAllText($ManifestPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
            foreach ($p in $json.plans) { $manifest[$p.file.ToLower()] = $p }
        } catch { Write-Log "plans-manifest.json could not be parsed: $_" 'WARN' }
    } else {
        Write-Log 'plans-manifest.json not found; integrity check disabled, file names used as plan names.' 'WARN'
    }
    $files = @(Get-ChildItem -LiteralPath $PlansDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -eq '.pow' } | Sort-Object Name)
    $catalog = @()
    foreach ($f in $files) {
        $m = $manifest[$f.Name.ToLower()]
        $catalog += [pscustomobject]@{
            File        = $f
            DisplayName = $(if ($m) { $m.displayName } else { $f.BaseName })
            FriendlyName= $(if ($m) { $m.friendlyName } else { $null })
            Sha256      = $(if ($m) { $m.sha256 } else { $null })
            Guid        = $(if ($m) { $m.guid } else { $null })
        }
    }
    return ,$catalog
}

# ---------------------------------------------------------------------------
# Staging: copy plan to a local ASCII path and validate it
# ---------------------------------------------------------------------------
$script:StageDir = $null
function Get-StageDir {
    if ($script:StageDir) { return $script:StageDir }
    $candidates = @((Join-Path $env:SystemRoot 'Temp\AlchemyPowerPlans'), (Join-Path ([IO.Path]::GetTempPath()) 'AlchemyPowerPlans'))
    foreach ($d in $candidates) {
        try {
            if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force -ErrorAction Stop | Out-Null }
            $probe = Join-Path $d 'probe.tmp'
            [IO.File]::WriteAllBytes($probe, [byte[]](1)); Remove-Item -LiteralPath $probe -Force
            $script:StageDir = $d
            return $d
        } catch { }
    }
    throw 'No writable local temp folder found for staging.'
}
function Get-StagedPlan {
    param($Plan)
    $src = $Plan.File.FullName
    try {
        $bytes = [IO.File]::ReadAllBytes($src)   # forces OneDrive hydration
    } catch {
        throw "Cannot read the file (OneDrive not synced, antivirus lock, or still inside a ZIP): $($_.Exception.Message)"
    }
    if ($bytes.Length -lt 4096) { throw "File is too small ($($bytes.Length) bytes) - incomplete download?" }
    if (-not ($bytes[0] -eq 0x72 -and $bytes[1] -eq 0x65 -and $bytes[2] -eq 0x67 -and $bytes[3] -eq 0x66)) {
        throw 'File is not a valid .pow (registry hive signature "regf" missing) - corrupted download?'
    }
    $hash = Get-Sha256Hex $bytes
    if ($Plan.Sha256 -and ($hash -ne $Plan.Sha256)) {
        Write-Log "  Hash mismatch for $($Plan.File.Name): file differs from the published version (modified or corrupted)." 'WARN'
    }
    $guid = $Plan.Guid
    if (-not $guid -or ($hash -ne $Plan.Sha256)) { $guid = Get-StableGuid $bytes }
    $dest = Join-Path (Get-StageDir) ("plan_{0}.pow" -f $guid.Substring(0, 8))
    [IO.File]::WriteAllBytes($dest, $bytes)    # new file: no Zone.Identifier, local disk, ASCII name
    return [pscustomobject]@{ Path = $dest; Guid = $guid.ToLower(); Bytes = $bytes.Length }
}

function Remove-Staged {
    param([string]$Path)
    if (-not $Path) { return }
    $dir = Split-Path -Parent $Path; $leaf = Split-Path -Leaf $Path
    Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name.StartsWith($leaf, [StringComparison]::OrdinalIgnoreCase) } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------------------
# Strategy C: rebuild a plan from the hive via powercfg value setters
# ---------------------------------------------------------------------------
function ConvertTo-UInt32Value {
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [byte[]]) {
        if ($Value.Length -lt 4) { return $null }
        return [BitConverter]::ToUInt32($Value, 0)
    }
    try { return [uint32]([int64]$Value -band 0xFFFFFFFFL) } catch { return $null }
}
function Import-PlanByRebuild {
    param([string]$StagedPath, [string]$TargetGuid, [string]$Name)
    $mount = 'ALCHEMY_POW_' + $TargetGuid.Substring(0, 8)
    $mountPs = "Registry::HKEY_LOCAL_MACHINE\$mount"
    $r = Invoke-Native -Exe $RegExe -Arguments @('load', "HKLM\$mount", $StagedPath)
    if ($r.ExitCode -ne 0) { Write-Log "    reg load failed: $($r.Output)" 'WARN'; return $null }
    $settings = @()
    $friendly = $Name; $desc = 'Imported by Alchemy Power Plan Tool (rebuild mode)'
    $personality = $null
    try {
        $rootProps = Get-ItemProperty -LiteralPath $mountPs -ErrorAction SilentlyContinue
        if ($rootProps.FriendlyName) {
            $fn = [string]$rootProps.FriendlyName
            $mm = [regex]::Match($fn, '^@[^,]+,-?\d+,(.*)$'); if ($mm.Success) { $fn = $mm.Groups[1].Value }
            if ($fn) { $friendly = $fn }
        }
        foreach ($sub in @(Get-ChildItem -LiteralPath $mountPs -ErrorAction SilentlyContinue)) {
            $subName = $sub.PSChildName
            if ($subName -notmatch "^$GuidRx$") { continue }
            $p = Get-ItemProperty -LiteralPath $sub.PSPath -ErrorAction SilentlyContinue
            if ($p -and (($p.PSObject.Properties.Name -contains 'ACSettingIndex') -or ($p.PSObject.Properties.Name -contains 'DCSettingIndex'))) {
                $settings += [pscustomobject]@{ Sub = $GUID_NO_SUBGRP; Setting = $subName; AC = (ConvertTo-UInt32Value $p.ACSettingIndex); DC = (ConvertTo-UInt32Value $p.DCSettingIndex) }
                if ($subName -eq $GUID_PERSONALITY) { $personality = ConvertTo-UInt32Value $p.ACSettingIndex }
            }
            foreach ($set in @(Get-ChildItem -LiteralPath $sub.PSPath -ErrorAction SilentlyContinue)) {
                if ($set.PSChildName -notmatch "^$GuidRx$") { continue }
                $q = Get-ItemProperty -LiteralPath $set.PSPath -ErrorAction SilentlyContinue
                if (-not $q) { continue }
                $names = $q.PSObject.Properties.Name
                if (($names -contains 'ACSettingIndex') -or ($names -contains 'DCSettingIndex')) {
                    $settings += [pscustomobject]@{ Sub = $subName; Setting = $set.PSChildName; AC = (ConvertTo-UInt32Value $q.ACSettingIndex); DC = (ConvertTo-UInt32Value $q.DCSettingIndex) }
                }
            }
        }
    } finally {
        $rootProps = $null; $p = $null; $q = $null; $sub = $null; $set = $null
        [GC]::Collect(); [GC]::WaitForPendingFinalizers()
        $unloaded = $false
        for ($i = 0; $i -lt 5 -and -not $unloaded; $i++) {
            $u = Invoke-Native -Exe $RegExe -Arguments @('unload', "HKLM\$mount")
            if ($u.ExitCode -eq 0) { $unloaded = $true } else { Start-Sleep -Milliseconds 400; [GC]::Collect() }
        }
        if (-not $unloaded) { Write-Log "    Could not unload temporary hive HKLM\$mount (harmless; it disappears after reboot)." 'WARN' }
    }
    if ($settings.Count -eq 0) { Write-Log '    No settings could be read from the hive.' 'WARN'; return $null }

    # Pick the closest built-in base: personality 0 = saver, 1 = high perf, 2 = balanced
    $bases = @()
    switch ($personality) { 0 { $bases += $GUID_SAVER } 1 { $bases += $GUID_HIGHPERF } 2 { $bases += $GUID_BALANCED } }
    $bases += @($GUID_HIGHPERF, $GUID_BALANCED)
    $created = $false
    foreach ($b in ($bases | Select-Object -Unique)) {
        if (-not (Test-SchemeExists $b)) { continue }
        $d = Invoke-PowerCfg @('/duplicatescheme', $b, $TargetGuid)
        if ($d.ExitCode -eq 0 -and (Test-SchemeExists $TargetGuid)) { $created = $true; Write-Log "    Base scheme: $b" -Quiet; break }
    }
    if (-not $created) {
        $d = Invoke-PowerCfg @('/duplicatescheme', 'SCHEME_CURRENT', $TargetGuid)
        if ($d.ExitCode -eq 0 -and (Test-SchemeExists $TargetGuid)) { $created = $true }
    }
    if (-not $created) { Write-Log '    Could not create a base scheme to rebuild into.' 'WARN'; return $null }
    Invoke-PowerCfg @('/changename', $TargetGuid, $friendly, $desc) | Out-Null

    $ok = 0; $fail = 0; $failed = @()
    foreach ($s in $settings) {
        foreach ($pair in @(@('/setacvalueindex', $s.AC), @('/setdcvalueindex', $s.DC))) {
            if ($null -eq $pair[1]) { continue }
            $res = Invoke-PowerCfg @($pair[0], $TargetGuid, $s.Sub, $s.Setting, [string]$pair[1])
            if ($res.ExitCode -eq 0) { $ok++ } else { $fail++; $failed += "$($s.Sub)/$($s.Setting)" }
        }
    }
    $uniqueFailed = @($failed | Select-Object -Unique)
    Write-Log ("    Rebuild applied {0} values, {1} rejected." -f $ok, $fail)
    if ($uniqueFailed.Count -gt 0) {
        Write-Log ("    {0} setting(s) do not exist on this Windows build/hardware and were skipped." -f $uniqueFailed.Count) 'WARN'
        foreach ($x in $uniqueFailed) { Write-Log "      skipped: $x" -Quiet }
    }
    return [pscustomobject]@{ Applied = $ok; Rejected = $fail }
}

# ---------------------------------------------------------------------------
# Robust import (A -> B -> C) with verification
# ---------------------------------------------------------------------------
function Install-Plan {
    param($Plan)
    $label = $Plan.DisplayName
    try { $st = Get-StagedPlan $Plan } catch { Write-Log "  [FAIL] $label - $($_.Exception.Message)" 'ERROR'; return $null }
    $guid = $st.Guid

    if (Test-SchemeExists $guid) {
        Write-Log "  [SKIP] $label - already installed ($guid)" 'OK'
        Remove-Staged $st.Path
        return [pscustomobject]@{ Guid = $guid; Method = 'existing' }
    }

    $result = $null
    # Strategy A
    $a = Invoke-PowerCfg @('/import', $st.Path, $guid)
    if (Test-SchemeExists $guid) {
        $result = [pscustomobject]@{ Guid = $guid; Method = 'import' }
    } else {
        if ($a.ExitCode -eq 0) { Write-Log '    powercfg reported success but the scheme was not created (silent failure).' 'WARN' -Quiet }
        # Strategy B
        $before = @((Get-SchemeList) | ForEach-Object { $_.Guid })
        $b = Invoke-PowerCfg @('/import', $st.Path)
        $after = @((Get-SchemeList) | ForEach-Object { $_.Guid })
        $new = @($after | Where-Object { $before -notcontains $_ })
        if ($new.Count -ge 1) {
            $result = [pscustomobject]@{ Guid = $new[0]; Method = 'import-autoguid' }
        } else {
            $m = [regex]::Match($b.Output, $GuidRx)
            if ($b.ExitCode -eq 0 -and $m.Success -and (Test-SchemeExists $m.Value)) {
                $result = [pscustomobject]@{ Guid = $m.Value.ToLower(); Method = 'import-autoguid' }
            }
        }
        # Strategy C
        if (-not $result) {
            Write-Log "    powercfg /import failed for $label; trying rebuild mode..." 'WARN'
            $c = Import-PlanByRebuild -StagedPath $st.Path -TargetGuid $guid -Name $label
            if ($c -and (Test-SchemeExists $guid)) {
                $result = [pscustomobject]@{ Guid = $guid; Method = ("rebuild ({0} values, {1} skipped)" -f $c.Applied, $c.Rejected) }
            }
        }
    }
    Remove-Staged $st.Path
    if ($result) {
        Write-Log ("  [OK]   {0}  ->  {1}  [{2}]" -f $label, $result.Guid, $result.Method) 'OK'
    } else {
        Write-Log ("  [FAIL] {0} - all import methods failed. Details are in the log." -f $label) 'ERROR'
        if ($a.Output) { Write-Log "    powercfg said: $($a.Output)" 'ERROR' }
    }
    return $result
}

function Set-ActivePlan {
    param([string]$Guid, [string]$Label)
    $r = Invoke-PowerCfg @('/setactive', $Guid)
    Start-Sleep -Milliseconds 300
    $active = Get-ActiveSchemeGuid
    if ($active -eq $Guid.ToLower()) {
        Write-Log "ACTIVATED: $Label ($Guid)" 'OK'
        return $true
    }
    Write-Log "Activation could not be verified. Active scheme is: $active" 'ERROR'
    if ($r.Output) { Write-Log "  powercfg said: $($r.Output)" 'ERROR' }
    if ($script:Env.PolicyScheme) {
        Write-Log "  A Group Policy forces the active plan ($($script:Env.PolicyScheme)). It overrides any plan you select." 'WARN'
    }
    return $false
}

# ---------------------------------------------------------------------------
# Environment checks (warnings only - nothing is changed)
# ---------------------------------------------------------------------------
$script:Env = $null
function Test-ModernStandby {
    # SYSTEM_POWER_CAPABILITIES.AoAc (byte offset 20) = Modern Standby. Returns $null if unknown.
    try {
        if (-not ('AlchemyPwrCaps' -as [type])) {
            Add-Type -ErrorAction Stop -TypeDefinition @'
using System.Runtime.InteropServices;
public static class AlchemyPwrCaps {
    [DllImport("powrprof.dll", SetLastError = true)]
    public static extern bool GetPwrCapabilities(byte[] caps);
}
'@
        }
        $buf = New-Object byte[] 256
        if ([AlchemyPwrCaps]::GetPwrCapabilities($buf)) { return ($buf[20] -ne 0) }
    } catch { }
    return $null
}
function Get-EnvironmentReport {
    $cv = Get-ItemProperty -LiteralPath 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
    $pw = Get-ItemProperty -LiteralPath 'Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Power' -ErrorAction SilentlyContinue
    $pol = Get-ItemProperty -LiteralPath 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Power\PowerSettings' -ErrorAction SilentlyContinue
    $drive = $null
    try { $drive = New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($ScriptDir)) } catch { }
    $oneDriveRoots = @($env:OneDrive, $env:OneDriveConsumer, $env:OneDriveCommercial) | Where-Object { $_ }
    $inOneDrive = $false
    foreach ($o in $oneDriveRoots) { if ($ScriptDir.StartsWith($o, [StringComparison]::OrdinalIgnoreCase)) { $inOneDrive = $true } }
    $placeholders = 0
    foreach ($f in @(Get-ChildItem -LiteralPath $PlansDir -File -ErrorAction SilentlyContinue)) {
        $attr = [int]$f.Attributes
        # 0x400000 RECALL_ON_DATA_ACCESS, 0x1000 OFFLINE, 0x400 REPARSE_POINT
        if (($attr -band 0x400000) -or ($attr -band 0x1000) -or ($attr -band 0x400)) { $placeholders++ }
    }
    $report = [pscustomobject]@{
        Product        = $cv.ProductName
        DisplayVersion = $cv.DisplayVersion
        Build          = ("{0}.{1}" -f $cv.CurrentBuildNumber, $cv.UBR)
        PSVersion      = $PSVersionTable.PSVersion.ToString()
        LanguageMode   = $ExecutionContext.SessionState.LanguageMode.ToString()
        Is64Process    = [Environment]::Is64BitProcess
        IsAdmin        = (Test-IsAdmin)
        ScriptDir      = $ScriptDir
        DriveType      = $(if ($drive) { $drive.DriveType.ToString() } else { 'unknown' })
        InOneDrive     = $inOneDrive
        Placeholders   = $placeholders
        InZipTemp      = ($ScriptDir -match '\\Temp\\.*\.zip' -or $ScriptDir -match '\\Temp\\Temp\d+_')
        NonAsciiPath   = ($ScriptDir -match '[^\x20-\x7E]')
        CsEnabled      = $pw.CsEnabled
        AoAcOverride   = $pw.PlatformAoAcOverride
        ModernStandby  = (Test-ModernStandby)
        PolicyScheme   = $pol.ActivePowerScheme
        ActiveScheme   = (Get-ActiveSchemeGuid)
    }
    $script:Env = $report
    return $report
}
function Show-EnvironmentWarnings {
    param($E)
    Write-Log ("Windows: {0} {1} build {2} | PowerShell {3} ({4}) | 64-bit process: {5}" -f $E.Product, $E.DisplayVersion, $E.Build, $E.PSVersion, $E.LanguageMode, $E.Is64Process)
    Write-Log ("Folder: {0}  [drive type: {1}]" -f $E.ScriptDir, $E.DriveType) -Quiet
    if ($E.InZipTemp) { Write-Log 'WARNING: the tool seems to be running from inside a ZIP. Extract the whole ZIP first (right-click > Extract All).' 'WARN' }
    if ($E.DriveType -eq 'Network' -or $E.DriveType -eq 'Removable') { Write-Log "NOTE: folder is on a $($E.DriveType) drive. Plans are copied to a local temp folder before import (handled automatically)." 'WARN' }
    if ($E.InOneDrive -or $E.Placeholders -gt 0) { Write-Log ("NOTE: folder is inside OneDrive ({0} online-only file(s)). Files are downloaded and copied locally before import (handled automatically)." -f $E.Placeholders) 'WARN' }
    if ($E.LanguageMode -ne 'FullLanguage') { Write-Log "WARNING: PowerShell is in $($E.LanguageMode) (WDAC/AppLocker/Smart App Control policy). Some steps may be blocked." 'WARN' }
    if ($E.PolicyScheme) { Write-Log "WARNING: Group Policy forces active power plan $($E.PolicyScheme). Plans will import, but Windows will keep switching back." 'WARN' }
    if ($E.ModernStandby -eq $true -or $E.CsEnabled -eq 1) {
        Write-Log 'NOTE: this PC uses Modern Standby (S0). Control Panel may show only "Balanced" even after import.' 'WARN'
        Write-Log '      Imported plans still exist and can be activated from this tool. This tool does NOT change Modern Standby.' 'WARN'
    }
}

# ---------------------------------------------------------------------------
# Modes
# ---------------------------------------------------------------------------
function Show-Banner {
    Clear-Host
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host ("     ALCHEMY TWEAKS - POWER PLAN TOOL  v{0}" -f $ToolVersion)   -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  !!! WARNING !!!' -ForegroundColor Red
    Write-Host '  Some of these plans have caused a BLUE SCREEN (BSOD) or' -ForegroundColor Red
    Write-Host '  instability on certain machines. Apply at your own risk.' -ForegroundColor Red
    Write-Host '  Recovery: run this tool again and choose [R], or in Safe Mode:' -ForegroundColor Yellow
    Write-Host "  powercfg /setactive $GUID_BALANCED" -ForegroundColor Yellow
    Write-Host ''
}
function Invoke-RestorePoint {
    param([string]$Label)
    $rp = Read-Host 'Create a System Restore Point first? (y/n)'
    if ($rp -notmatch '^[Yy]') { return }
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description ("Before power plan " + $Label) -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Write-Log 'Restore point created.' 'OK'
    } catch {
        Write-Log "Restore point not created: $($_.Exception.Message)" 'WARN'
        Write-Log '(Windows allows one restore point per 24h by default, or System Protection is off.)' 'WARN'
    }
}
function Invoke-Restore {
    if (Test-SchemeExists $GUID_BALANCED) {
        [void](Set-ActivePlan -Guid $GUID_BALANCED -Label 'Windows Balanced')
        return
    }
    Write-Log 'The default Balanced plan is missing from this system (removed by another tweak).' 'WARN'
    $ans = Read-Host 'Restore Windows default plans with "powercfg /restoredefaultschemes"? This REMOVES all custom plans. (y/n)'
    if ($ans -match '^[Yy]') {
        Invoke-PowerCfg @('/restoredefaultschemes') | Out-Null
        [void](Set-ActivePlan -Guid $GUID_BALANCED -Label 'Windows Balanced')
    }
}
function Invoke-Apply {
    param($Catalog)
    Write-Host '  Tested power plans:' -ForegroundColor Green
    for ($i = 0; $i -lt $Catalog.Count; $i++) { Write-Host ('    [{0,2}] {1}' -f ($i + 1), $Catalog[$i].DisplayName) }
    Write-Host ''
    Write-Host '    [ A] Import ALL plans (no activation)' -ForegroundColor Cyan
    Write-Host '    [ R] Restore the default Windows "Balanced" plan' -ForegroundColor Cyan
    Write-Host '    [ D] Diagnose (creates a log to attach to a bug report)' -ForegroundColor Cyan
    Write-Host '    [ C] Clean up duplicate plans from older versions of this tool' -ForegroundColor Cyan
    Write-Host '    [ Q] Quit' -ForegroundColor Cyan
    Write-Host ''
    $choice = (Read-Host 'Enter the plan number or a letter').Trim()
    if ($choice -match '^[Qq]$') { return }
    if ($choice -match '^[Rr]$') { Invoke-Restore; return }
    if ($choice -match '^[Aa]$') { Invoke-ImportAll $Catalog; return }
    if ($choice -match '^[Dd]$') { Invoke-Diagnose $Catalog; return }
    if ($choice -match '^[Cc]$') { Invoke-Cleanup $Catalog; return }
    $n = 0
    if (-not [int]::TryParse($choice, [ref]$n) -or $n -lt 1 -or $n -gt $Catalog.Count) { Write-Log 'Invalid choice.' 'ERROR'; return }
    $plan = $Catalog[$n - 1]
    Write-Log ("Selected: {0}   ({1})" -f $plan.DisplayName, $plan.File.Name) 'STEP'
    Invoke-RestorePoint $plan.DisplayName
    $ok = Read-Host 'Are you sure you want to APPLY this plan? (y/n)'
    if ($ok -notmatch '^[Yy]') { Write-Log 'Cancelled.' 'WARN'; return }
    $res = Install-Plan $plan
    if (-not $res) {
        Write-Log 'The plan could not be installed. Run [D] Diagnose and attach the log to your report.' 'ERROR'
        return
    }
    if (Set-ActivePlan -Guid $res.Guid -Label $plan.DisplayName) {
        Write-Log 'If the system becomes unstable: run again and press [R] to restore Balanced.' 'WARN'
    }
}
function Invoke-ImportAll {
    param($Catalog)
    Write-Log ("Importing {0} power plans (already installed plans are skipped)..." -f $Catalog.Count) 'STEP'
    $ok = 0; $skip = 0; $fail = 0
    foreach ($p in $Catalog) {
        $r = Install-Plan $p
        if (-not $r) { $fail++ } elseif ($r.Method -eq 'existing') { $skip++ } else { $ok++ }
    }
    Write-Log ''
    Write-Log ("Done. Imported {0}, already present {1}, failed {2} (of {3})." -f $ok, $skip, $fail, $Catalog.Count) $(if ($fail) { 'WARN' } else { 'OK' })
    Write-Log 'Open Power Options with: powercfg.cpl   (use "Show additional plans" if needed)'
    if ($fail -gt 0) { Write-Log 'Some plans failed. Run Diagnose ([D]) and attach the log to your GitHub issue.' 'WARN' }
}
function Invoke-Diagnose {
    param($Catalog)
    Write-Log 'Running diagnostics (no permanent changes)...' 'STEP'
    $E = $script:Env
    $E | Format-List | Out-String | ForEach-Object { Write-Log $_.TrimEnd() -Quiet }
    Write-Log ("Schemes installed: {0}" -f (Get-SchemeList).Count)
    $bad = 0
    foreach ($p in $Catalog) {
        try { $st = Get-StagedPlan $p; Remove-Staged $st.Path }
        catch { $bad++; Write-Log "  File problem: $($p.File.Name) - $($_.Exception.Message)" 'ERROR' }
    }
    Write-Log ("File check: {0} of {1} plan files readable and valid." -f ($Catalog.Count - $bad), $Catalog.Count) $(if ($bad) { 'WARN' } else { 'OK' })
    # Round-trip test with the smallest plan into a throw-away GUID
    $probe = $Catalog | Sort-Object { $_.File.Length } | Select-Object -First 1
    if ($probe) {
        $tmpGuid = [guid]::NewGuid().ToString()
        try {
            $st = Get-StagedPlan $probe
            $a = Invoke-PowerCfg @('/import', $st.Path, $tmpGuid)
            $okA = Test-SchemeExists $tmpGuid
            Write-Log ("Test powercfg /import: exit {0}, scheme created: {1}" -f $a.ExitCode, $okA) $(if ($okA) { 'OK' } else { 'ERROR' })
            if ($okA) { Invoke-PowerCfg @('/delete', $tmpGuid) | Out-Null }
            else {
                $c = Import-PlanByRebuild -StagedPath $st.Path -TargetGuid $tmpGuid -Name 'Alchemy diagnostic test'
                $okC = Test-SchemeExists $tmpGuid
                Write-Log ("Test rebuild mode: scheme created: {0}" -f $okC) $(if ($okC) { 'OK' } else { 'ERROR' })
                if ($okC) { Invoke-PowerCfg @('/delete', $tmpGuid) | Out-Null }
            }
            Remove-Staged $st.Path
        } catch { Write-Log "Test failed: $($_.Exception.Message)" 'ERROR' }
    }
    Write-Log 'Diagnostics finished. Attach the log file below to your GitHub issue.' 'OK'
}
function Invoke-Cleanup {
    param($Catalog)
    Write-Log 'Looking for duplicate copies created by older versions of this tool...' 'STEP'
    $active = Get-ActiveSchemeGuid
    $stable = @($Catalog | ForEach-Object { if ($_.Guid) { $_.Guid.ToLower() } })
    # Match by plan name, but never touch built-in schemes or generic Microsoft names.
    $generic = @('high performance', 'ultimate performance', 'balanced', 'power saver')
    $names = @($Catalog | ForEach-Object { $_.FriendlyName } | Where-Object { $_ -and ($generic -notcontains $_.ToLower()) })
    $targets = @()
    foreach ($s in (Get-SchemeList)) {
        if ($BuiltInSchemes -contains $s.Guid) { continue }
        if ($stable -contains $s.Guid) { continue }
        if ($s.Guid -eq $active) { continue }
        if ($names -contains $s.Name) { $targets += $s }
    }
    if ($targets.Count -eq 0) { Write-Log 'Nothing to clean up.' 'OK'; return }
    Write-Host ''
    foreach ($t in $targets) { Write-Host ("    {0}  {1}" -f $t.Guid, $t.Name) }
    Write-Host ''
    $ans = Read-Host ("Delete these {0} duplicate plan(s)? The active plan is never touched. Type YES to confirm" -f $targets.Count)
    if ($ans -cne 'YES') { Write-Log 'Cleanup cancelled.' 'WARN'; return }
    $n = 0
    foreach ($t in $targets) { $r = Invoke-PowerCfg @('/delete', $t.Guid); if ($r.ExitCode -eq 0) { $n++ } }
    Write-Log ("Removed {0} of {1} duplicate plan(s)." -f $n, $targets.Count) 'OK'
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
if (-not (Test-IsAdmin)) { Request-Elevation }

Initialize-Log
Show-Banner

if (-not (Test-Path -LiteralPath $PowerCfg)) { Write-Log "powercfg.exe not found at $PowerCfg" 'ERROR'; Exit-Tool 2 }
if (-not (Test-Path -LiteralPath $PlansDir)) {
    Write-Log "The 'plans' folder was not found next to this script: $PlansDir" 'ERROR'
    Write-Log 'If you opened the ZIP without extracting it, extract the whole ZIP first (right-click > Extract All).' 'WARN'
    Exit-Tool 2
}
$catalog = Get-PlanCatalog
if ($catalog.Count -eq 0) { Write-Log 'No .pow files found in the plans folder.' 'ERROR'; Exit-Tool 2 }

$envReport = Get-EnvironmentReport
Show-EnvironmentWarnings $envReport
Write-Host ''

switch ($Mode) {
    'ImportAll' { Invoke-ImportAll $catalog }
    'Diagnose'  { Invoke-Diagnose $catalog }
    'Cleanup'   { Invoke-Cleanup $catalog }
    'Restore'   { Invoke-Restore }
    default     { Invoke-Apply $catalog }
}
Exit-Tool 0
