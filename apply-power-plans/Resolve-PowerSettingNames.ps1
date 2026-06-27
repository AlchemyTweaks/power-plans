# ============================================================
#  Resolve-PowerSettingNames.ps1
#  Reads the OFFICIAL friendly name of EVERY Windows power
#  setting from your own registry (the same data the
#  "Power Settings Explorer" tool shows, hidden ones included),
#  then rewrites index.html so no setting appears as a raw GUID.
#  No administrator rights needed. Safe: read-only on registry.
# ============================================================

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
$htmlPath = Join-Path $here 'index.html'
$root = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings'

Write-Host 'Reading power-setting names from the registry...' -ForegroundColor Cyan

# API to resolve "@file,-id" indirect strings to real text
Add-Type -Namespace Win32 -Name Shl -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("shlwapi.dll", CharSet=System.Runtime.InteropServices.CharSet.Unicode)]
public static extern int SHLoadIndirectString(string pszSource, System.Text.StringBuilder pszOut, int cchOut, System.IntPtr ppvReserved);
'@

function Resolve-Str([string]$s){
    if ([string]::IsNullOrEmpty($s)) { return $s }
    if ($s.StartsWith('@')) {
        $sb = New-Object System.Text.StringBuilder 2048
        if ([Win32.Shl]::SHLoadIndirectString($s, $sb, 2048, [IntPtr]::Zero) -eq 0) { return $sb.ToString() }
        return $s
    }
    return $s
}
function FriendlyName([string]$keyPath){
    try { return (Get-ItemProperty -Path $keyPath -Name FriendlyName -ErrorAction Stop).FriendlyName } catch { return $null }
}

$subs = @{}; $sets = @{}
$guidRe = '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'

Get-ChildItem -Path $root -ErrorAction SilentlyContinue | ForEach-Object {
    $l1 = $_; $g1 = $l1.PSChildName.ToLower()
    if ($g1 -notmatch $guidRe) { return }
    $fn1 = Resolve-Str (FriendlyName $l1.PSPath)
    $kids = @(Get-ChildItem -Path $l1.PSPath -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match $guidRe })
    if ($kids.Count -gt 0) {
        if ($fn1) { $subs[$g1] = $fn1 }              # this level = subgroup
        foreach ($c in $kids) {
            $g2 = $c.PSChildName.ToLower()
            $fn2 = Resolve-Str (FriendlyName $c.PSPath)
            if ($fn2) { $sets[$g2] = $fn2 }           # this level = setting
        }
    } else {
        if ($fn1) { $sets[$g1] = $fn1 }               # leaf = no-subgroup setting
    }
}

Write-Host ("Resolved {0} subgroups and {1} settings." -f $subs.Count, $sets.Count) -ForegroundColor Green

# write names.json (for reference)
$obj = [ordered]@{ subgroups = $subs; settings = $sets }
$json = $obj | ConvertTo-Json -Depth 5 -Compress
Set-Content -Path (Join-Path $here 'names.json') -Value $json -Encoding UTF8

# patch index.html between the NAMES markers
if (Test-Path $htmlPath) {
    $html = Get-Content -Path $htmlPath -Raw -Encoding UTF8
    $replacement = '/*NAMES_START*/' + $json + '/*NAMES_END*/'
    $rx = [regex]'(?s)/\*NAMES_START\*/.*?/\*NAMES_END\*/'
    if ($rx.IsMatch($html)) {
        $html = $rx.Replace($html, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $replacement }, 1)
        Set-Content -Path $htmlPath -Value $html -Encoding UTF8
        Write-Host 'index.html updated - all setting names are now filled from your system.' -ForegroundColor Green
    } else {
        Write-Host 'Could not find the NAMES markers in index.html (was it edited?). names.json was still written.' -ForegroundColor Yellow
    }
} else {
    Write-Host 'index.html not found next to this script; names.json was written.' -ForegroundColor Yellow
}

Write-Host ''
Read-Host 'Done. Press Enter to exit'
