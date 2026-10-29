# Kept for backward compatibility. All logic now lives in PowerPlanTool.ps1.
& (Join-Path $PSScriptRoot 'PowerPlanTool.ps1') -Mode Apply
exit $LASTEXITCODE
