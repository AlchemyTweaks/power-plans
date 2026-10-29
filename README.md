# Power Plans: FPS & Latency Analysis

The 39 Windows power plans tested in the video, the script that applies any of them, and the raw measurement data (FPS and latency).

> [!WARNING]
> Some of these plans can trigger a blue screen (BSOD) or instability on certain hardware. Apply at your own risk. Create a System Restore Point first; the apply script does this for you. Recovery steps are in [Restore to default](#restore-to-default).

> [!IMPORTANT]
> **Import issues on recent Windows 11 builds (24H2 / 25H2 / 26H2): new v2 scripts (2026-10-29).**
> The original script ran `powercfg /import` directly on the downloaded file and trusted its exit code.
> When the folder sits in OneDrive (online-only files), on a USB or network drive, inside an unextracted ZIP,
> or under a path with special characters, the import can fail or report success without creating the plan.
> v2 copies each plan to a local temp folder first, verifies every import, falls back to two alternative
> import methods, and never creates duplicates. **Download the repository again** and use the new scripts.
> We have not been able to confirm a single root cause for every report yet. Still failing? Run `Diagnose (attach log to bug reports).bat` and open an issue with the log attached.

## Contents

| Folder | Contents |
| --- | --- |
| `apply-power-plans/` | The 39 `.pow` plans and a one-click apply script. |
| `performance-analysis/` | Measurement data: `FPS Analysis.xlsx`, `Latency Analysis.xlsx`. |
| `presentation/` | Slide deck with the FPS/latency results. |

## Apply a plan

1. Download the repo (Code > Download ZIP).
2. Open `apply-power-plans/` and run `Apply Power Plan (Run as Admin).bat`.
3. Select a plan by name. It is imported, verified, and set as the active Windows power plan.

The script self-elevates to admin and offers to create a restore point before applying.
Extract the ZIP first; do not run the `.bat` from inside the ZIP preview.

### Import all plans at once

Run `Import All Power Plans (Run as Admin).bat` in `apply-power-plans/`. Every plan is registered in
Control Panel > Power Options (`powercfg.cpl`) without being activated. Each plan gets a stable GUID derived
from its file, so running it again skips plans that are already installed instead of creating duplicates.

### How the v2 import works

For every plan, `PowerPlanTool.ps1`:

1. Reads the `.pow` file fully and writes a copy to a local temp folder with an ASCII-only name
   (forces OneDrive to download the file, removes the internet zone mark, avoids USB/network/Unicode paths).
2. Checks the file: registry hive signature and SHA-256 against `plans-manifest.json`.
3. Imports it with `powercfg /import` into a stable GUID and **verifies** that the plan now exists.
4. If that fails, retries `powercfg /import` without a GUID and detects the new plan.
5. If that also fails, rebuilds the plan: loads the `.pow` as a temporary registry hive, duplicates the
   closest built-in plan and applies every setting with `powercfg /setacvalueindex` / `/setdcvalueindex`.
   Settings that do not exist on your Windows build or hardware are skipped and listed in the log.
6. Activates the plan and verifies it with `powercfg /getactivescheme`. Group Policy overrides and
   Modern Standby (S0) systems are detected and reported; the tool never changes them.

Every run writes a log to `apply-power-plans/logs/`.

The Apply menu also offers `[C]` to remove duplicate copies left by the old script (by plan name; built-in
plans and the active plan are never touched, and you must type `YES` to confirm).

### Troubleshooting

| Symptom | Cause | What to do |
| --- | --- | --- |
| Window closes immediately or "plans folder not found" | Running from inside the ZIP | Right-click the ZIP > Extract All, run the `.bat` from the extracted folder |
| "running scripts is disabled on this system" | Script policy set by an administrator (work/school PC) | Not bypassed by this tool; ask the PC administrator |
| Only "Balanced" is visible in Control Panel | Modern Standby (S0) laptop/handheld | Plans are installed; activate them from the tool menu |
| Plan switches back by itself | Group Policy, OEM utility (Armoury Crate, Lenovo Vantage, etc.) or "Power mode" tools | The log names the policy if one exists; disable the OEM power control |
| `[FAIL]` on all methods | Unknown | Run `Diagnose (attach log to bug reports).bat` and open an issue with the log |

### Inspect the plans

Open `apply-power-plans/index.html` in any browser. It lists every plan, its AC/DC values, and the similarity percentage between near-duplicate plans.

Tweaker plans often use hidden power settings that render as raw GUIDs. To resolve every setting name, run `Resolve-PowerSettingNames.ps1` once (no admin required; it only reads the registry), then reopen `index.html`.

## Measurement data

`performance-analysis/` holds the results:

- `FPS Analysis.xlsx`: frames per second per plan.
- `Latency Analysis.xlsx`: input and system latency per plan.

Plan names are identical across the spreadsheets, `index.html`, and the `.pow` files, so each result maps directly to a plan.

## Restore to default

- Re-run `Apply Power Plan (Run as Admin).bat` and press `R` to switch back to the Windows Balanced plan. If a previous tweak deleted the Balanced plan, the tool offers `powercfg /restoredefaultschemes` (this removes custom plans).
- If the system will not boot, enter Safe Mode (Shift + Restart > Troubleshoot > Advanced > Startup Settings > Restart > 4 / F4), open Command Prompt, and run:

  ```
  powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e
  ```

  This reactivates the default Balanced plan.

## Notes

Plans are kept under their original file names. Credit for each plan belongs to its author.
