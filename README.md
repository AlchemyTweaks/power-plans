# Power Plans: FPS & Latency Analysis

The 39 Windows power plans tested in the video, the script that applies any of them, and the raw measurement data (FPS and latency).

> [!WARNING]
> Some of these plans can trigger a blue screen (BSOD) or instability on certain hardware. Apply at your own risk. Create a System Restore Point first; the apply script does this for you. Recovery steps are in [Restore to default](#restore-to-default).

## Contents

| Folder | Contents |
| --- | --- |
| `apply-power-plans/` | The 39 `.pow` plans and a one-click apply script. |
| `performance-analysis/` | Measurement data: `FPS Analysis.xlsx`, `Latency Analysis.xlsx`. |
| `presentation/` | Slide deck with the FPS/latency results. |

## Apply a plan

1. Download the repo (Code > Download ZIP).
2. Open `apply-power-plans/` and run `Apply Power Plan (Run as Admin).bat`.
3. Select a plan by name. It is set as the active Windows power plan.

The script self-elevates to admin and offers to create a restore point before applying.

### Inspect the plans

Open `apply-power-plans/index.html` in any browser. It lists every plan, its AC/DC values, and the similarity percentage between near-duplicate plans.

Tweaker plans often use hidden power settings that render as raw GUIDs. To resolve every setting name, run `Resolve-PowerSettingNames.ps1` once (no admin required; it only reads the registry), then reopen `index.html`.

## Measurement data

`performance-analysis/` holds the results:

- `FPS Analysis.xlsx`: frames per second per plan.
- `Latency Analysis.xlsx`: input and system latency per plan.

Plan names are identical across the spreadsheets, `index.html`, and the `.pow` files, so each result maps directly to a plan.

## Restore to default

- Re-run `Apply Power Plan (Run as Admin).bat` and press `R` to switch back to the Windows Balanced plan.
- If the system will not boot, enter Safe Mode (Shift + Restart > Troubleshoot > Advanced > Startup Settings > Restart > 4 / F4), open Command Prompt, and run:

  ```
  powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e
  ```

  This reactivates the default Balanced plan.

## Notes

Plans are kept under their original file names. Credit for each plan belongs to its author.
