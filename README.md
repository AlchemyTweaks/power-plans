# Power Plans — FPS & Latency Analysis

Everything shown in the video, in one place. These are the **39 Windows power plans** that were
actually tested, a tool to apply any of them with one click, and the full performance data
(FPS + latency) behind the results.

> [!WARNING]
> Some of these plans can cause a **blue screen (BSOD)** or instability on some machines.
> Apply them at your own risk and **create a System Restore Point first** (the apply tool offers
> this automatically). See [Restore to normal](#restore-to-normal) if anything goes wrong.

---

## What's in here

| Folder | What it is |
| --- | --- |
| **[apply-power-plans/](apply-power-plans/)** | The 39 tested `.pow` plans + a one-click tool to apply any of them. |
| **[performance-analysis/](performance-analysis/)** | The raw test data: `FPS Analysis.xlsx` and `Latency Analysis.xlsx`. |
| **[presentation/](presentation/)** | The slide deck summarizing the FPS & latency findings. |

---

## Quick start — apply a power plan

1. Download the repo (green **Code → Download ZIP** button at the top of this page).
2. Open the **apply-power-plans** folder and double-click **`Apply Power Plan (Run as Admin).bat`**.
3. Pick a plan by its name → it becomes your active Windows power plan.

That's it. The tool requests admin rights automatically and offers to make a restore point first.

### Browse every plan and its settings
Open **`apply-power-plans/index.html`** in any browser. It lists all 39 plans, shows each one's
AC/DC values, and tells you which plans are near-duplicates of each other.

> **Tip:** many tweaker plans use hidden power settings that show up as raw GUIDs. To fill in
> **every** setting name accurately, double-click `Resolve-PowerSettingNames.ps1` once (no admin
> needed — it only reads your own Windows registry), then re-open `index.html`.

---

## The performance data

The numbers behind everything are in **[performance-analysis/](performance-analysis/)**:

- **FPS Analysis.xlsx** — frames-per-second results across the tested plans.
- **Latency Analysis.xlsx** — input / system latency results.

The same plan names are used in the spreadsheets, the `index.html` browser, and the `.pow` files,
so you can match a result to a plan instantly.

---

## Restore to normal

If a plan causes problems:

- **Easy way:** re-run `Apply Power Plan (Run as Admin).bat` and press **[R]** to switch back to
  the Windows **Balanced** plan.
- **If the PC won't boot:** enter Safe Mode (hold **Shift + Restart** -> Troubleshoot -> Advanced ->
  Startup Settings -> Restart -> press **4 / F4**), open Command Prompt and run:

  ```
  powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e
  ```

  (that restores the default Balanced plan).

---

*These plans were collected for testing and comparison. Credit for each plan goes to its original
creator — names are kept exactly as released.*
