=====================================================================
 POWER PLAN MANAGER  (Tested plans edition)
=====================================================================

This kit contains ONLY the power plans you actually tested in the
"POWER PLANS - FPS Analysis.xlsx" file - all 39 of them. Each plan is
labelled with the same name it has in that Excel.

---------------------------------------------------------------------
WHAT THIS FOLDER CONTAINS
---------------------------------------------------------------------
  index.html ................ Double-click to open (any browser).
                              Browse every tested plan, see all its
                              settings (AC / DC values) and which
                              plans are near-duplicates of each other.
  plans\ .................... The 39 tested power plans (.pow files).
  Apply Power Plan (Run as Admin).bat ... Double-click -> pick a plan
                              by its Excel name -> it becomes active.
                              Requests admin automatically.
  Apply-PowerPlan.ps1 ....... The apply script (run by the .bat).
  Resolve-PowerSettingNames.ps1 ... Run once to fill EVERY setting
                              name (see "SETTING NAMES" below).
  README.txt ................ This file.

---------------------------------------------------------------------
SETTING NAMES  (important)
---------------------------------------------------------------------
  index.html ships with a built-in dictionary that names the settings
  that can be named with certainty. Many tweaker plans also use HIDDEN
  / advanced power settings whose names are NOT publicly documented and
  must NOT be guessed (wrong names would hurt accuracy).

  To fill in EVERY remaining name 100% accurately:
    1. Double-click  Resolve-PowerSettingNames.ps1
       (no admin needed; it only READS your registry)
    2. It reads the official FriendlyName of every power setting from
       your own Windows - exactly the same data the "Power Settings
       Explorer" tool shows, hidden settings included - and rewrites
       index.html so nothing appears as a raw GUID.
    3. Re-open index.html. Done. You can then hand the whole folder to
       other users with all names already filled in.

  (If running .ps1 is blocked, right-click it -> Run with PowerShell.)

---------------------------------------------------------------------
!!! WARNING - RISK OF BLUE SCREEN (BSOD) !!!
---------------------------------------------------------------------
  Some of these plans have caused a BLUE SCREEN or instability on at
  least one machine. Apply them at your own risk.

  RECOMMENDED: create a System Restore Point first (the apply script
  offers this automatically).

  IF THE PC WILL NOT BOOT:
    1. Enter Safe Mode (hold Shift + Restart -> Troubleshoot ->
       Advanced -> Startup Settings -> Restart -> 4 / F4).
    2. Open Command Prompt and run:
         powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e
       (restores the default "Balanced" plan).
    Or re-run the .bat and press [R].

---------------------------------------------------------------------
DUPLICATE ANALYSIS (39 tested plans)
---------------------------------------------------------------------
  - No plan is a 100% duplicate of another (they all differ).
  - Closest pairs (near-duplicates, almost identical settings/values):
      * BEYOND-PERFORMANCE-AMD-INTEL-V1  ~  Jackpot2026                       (93%)
      * LLG-CERTIFIED-FOR-PARKING+E-CORES-FIX ~ LLG-CERTIFIED-FOR-NON-K-CPUs  (92.3%)
      * BEYOND-PERFORMANCE-AMD-INTEL-V1  ~  LLG-CERTIFIED-FOR-NON-K-CPUs      (92%)
      * Reticle                          ~  FPSHEAVEN2026                     (90.5%)
      * Arsenza-PowerPlan-INTEL          ~  Arsezna-PowerPlan-ALL-CPU         (90%)
      * EndGame                          ~  Prodazin                          (89%)
  index.html shows, for each plan, which others it resembles and by how %.

---------------------------------------------------------------------
RESTORE TO NORMAL
---------------------------------------------------------------------
  Run "Apply Power Plan (Run as Admin).bat" and press [R] to switch
  back to the Windows "Balanced" plan.
