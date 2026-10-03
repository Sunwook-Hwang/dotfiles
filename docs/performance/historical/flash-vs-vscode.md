# ***FLASH*** + Neovide vs VS Code: exploratory GUI comparison

> Historical experiment: paths, environments and feature descriptions refer to
> the recorded revision, not current installation instructions. See the
> [performance index](../README.md) for current measurements.

[English](flash-vs-vscode.md) | [한국어](flash-vs-vscode.ko.md)

***FLASH* had a much smaller sampled process-RSS sum even with a GUI attached.**
This experiment compares full ***FLASH* + Neovide** against **VS Code Desktop**,
not terminal-only Neovim against a complete graphical application. It is an
exploratory resource and automation benchmark, not a key-to-screen latency test.

The 2,000-line fixture's settled RSS sum was about **172 MiB vs 1,548 MiB**.
This metric adds per-process RSS and can count shared pages more than once:
it is **not physical RAM saved**, total GPU memory, or a peak-memory result.
Final ordinary-file edit-command medians were lower for ***FLASH***, but run ranges
overlapped. Focus commands completed sooner through ***FLASH***'s API path. Those different automation
paths do not establish a corresponding human-perceived speed ratio.

## Environment

- Date: 2026-09-28; configuration revision `8ba69f0a521a309a3c68a4158a5b7802aafa0644`.
- Mac mini, Apple M4, 10 CPU cores, 16 GB RAM, macOS 27.0 (26A428), arm64.
- Neovim 0.12.5 with this repository's ***FLASH*** configuration; Neovide 0.16.2.
- VS Code 1.139.1, a fresh user-data, shared-data and extensions directory per run.
- Three fresh processes per application, alternating order: **six launches**.
  Each launch performs both file scenarios, for **12 scenario executions**.
- ***FLASH*** LSP activation is disabled. VS Code runs in **normal application mode, not extension development mode**,
  with only the local measurement extension in its isolated extensions directory.
  Existing user extensions are not loaded; builtin extensions remain enabled. No Python LSP
  extension is installed for this experiment. Builtin Git, authentication,
  JSON/TypeScript-related services can still activate; active IDs are recorded.
- Each ***FLASH*** process uses fresh config/data/state/cache directories, directly
  loads the repository's init.lua, and runs the actual `nvim` binary under
  Neovide, bypassing the user's terminal-mode launcher. No swap or ShaDa.
- VS Code updates, extension updates, telemetry, experiments, workspace trust
  prompts, hot exit, and AI features are disabled in its temporary settings.
  No user configuration files are edited. Workloads use only generated files.
- 1200 × 800 windows were requested. VS Code passes that unrecognized switch
  through to Chromium; actual window and editor viewport equality was **not
  verified**. This is another reason not to infer rendering superiority.
- OS filesystem caches and background desktop activity were not controlled.

The [raw data](flash-vs-vscode-results.json) includes every final run, per-process
RSS breakdowns without local paths/PIDs, validation flags and fixture hashes.
Pilot runs and extension-development-mode runs are excluded from these summaries.
The measurement extension itself still adds overhead; that cost is not subtracted.

## Results

Values are **median (minimum–maximum)** across three runs. RSS rows are comparable
resource-accounting snapshots with the stated caveats. Command/API rows describe
work through each application's own automation interface, **not identical
rendering workloads**. Do not divide them to advertise a key-latency multiplier.

| Metric                                |        ***FLASH*** + Neovide |                   VS Code |
| ------------------------------------- | ---------------------: | ------------------------: |
| Document/automation readiness (ms)    | 155.18 (151.70–161.17) | 1168.56 (1163.36–1221.26) |
| 2k file: settled RSS sum (MiB)        | 171.75 (171.69–171.84) | 1548.34 (1544.39–1561.98) |
| 2k file: post-workload RSS sum (MiB)  | 174.98 (174.81–175.16) | 1694.44 (1673.06–1787.70) |
| 60k file: settled RSS sum (MiB)       | 176.97 (176.89–177.28) | 1747.31 (1708.03–1813.92) |
| 60k file: post-workload RSS sum (MiB) | 178.58 (178.41–178.67) | 1812.59 (1759.78–1829.00) |
| Open 60k file: API time (ms)          |       8.58 (8.46–8.85) |       44.26 (37.96–48.37) |
| 2k: 200 cursor commands (ms)          |    62.70 (59.87–63.18) |       72.37 (69.32–80.03) |
| 2k: 50 edits (ms)                     |    27.25 (26.69–27.35) |       32.47 (22.04–36.60) |
| 2k: 50 focus commands (ms)            |    18.07 (17.87–18.14) |    347.02 (316.64–397.00) |
| 60k: 200 cursor commands (ms)         |    11.29 (10.89–11.32) |       77.80 (63.89–86.46) |
| 60k: 50 edits (ms)                    |       3.32 (3.19–3.35) |       51.37 (35.72–53.72) |
| 60k: 50 focus commands (ms)           |       6.52 (6.28–6.64) |    292.98 (283.72–310.01) |

## Protocol

Files contain `value_N = N` for N=0–1999 or N=0–59999, encoded in UTF-8 with LF
and a final newline. They are outside Git. VS Code counts an extra final empty
line (2,001 / 60,001); ***FLASH*** reports 2,000 / 60,000 for the same bytes.

1. Launch an isolated application process and open the small Python file.
   Record elapsed time until the measurement driver reports the document ready.
   VS Code uses extension activation plus `showTextDocument`; ***FLASH*** uses a
   scheduled `VimEnter` callback and `redraw!`. This is **automation readiness**,
   not first presented frame, all-background-work completion, or OS-cold startup.
2. Activate/open the small file, signal the parent, wait three seconds and take
   a process-tree RSS snapshot. The small-file activation time is retained in
   raw data only, since the document was already opened during startup.
3. Move down 200 logical lines and verify the final cursor position. ***FLASH*** uses
   `normal! j`, explicit `CursorMoved`, redraw and a zero-duration event-loop
   yield. VS Code awaits 200 `cursorMove` commands through its extension API.
4. Replace lines 2–51 with `# benchmark edit N` and verify all 50 replacements.
   ***FLASH*** uses buffer APIs, explicit `TextChanged`, redraw and event-loop yields.
   VS Code awaits individual `TextEditor.edit` operations. Neither measures
   keyboard typing, completion or formatter work.
5. Open the same document in two side-by-side views. Alternate focus 50 times.
   ***FLASH*** uses window APIs and redraw; VS Code awaits editor-group focus commands.
   Verify two editor views; VS Code also verifies they show the same document.
6. Save the temporary fixture, signal completion, wait three seconds and take
   another memory snapshot. Close the extra split, then repeat steps 2–6 for
   the large file. Large-file opening is timed separately. The small document
   remains loaded, so later RSS includes accumulated state, not a fresh-large-file
   baseline. ***FLASH***'s large-buffer restriction flag is verified on the large file.
7. Collect the result and quit only the isolated application instance. All six
   final runs exited successfully with the expected cursor/edit/view checks.

Memory is sampled with `ps` for the launched main PID and its descendants.
This includes **Neovide and Neovim** on one side and the **Code main, renderer,
GPU/helpers and extension hosts** present in the process tree on the other.
The parent harness, OS WindowServer, unrelated editors and non-descendant system
services are excluded. Sum RSS is not unique resident memory: shared mappings
may be counted repeatedly. No claim of physical memory savings follows directly.

The local VS Code measurement extension uses the documented
[editor and command APIs](https://code.visualstudio.com/api/references/vscode-api).
Isolation uses separate data and extension directories, following the
[VS Code CLI isolation options](https://code.visualstudio.com/docs/configure/command-line#_isolating-vs-code-instances).

## What can be concluded

For this local desktop setup, ***FLASH* + Neovide had a substantially smaller
process-RSS sum**, including GUI costs. That supports a narrower claim about
resource overhead, not that VS Code needs exactly this much physical RAM in
all installations. GUI overhead is significant: do not reuse the earlier
terminal-only ***FLASH*** memory numbers as the GUI application's footprint.

Small-file edit-command medians were about 27 ms for ***FLASH*** and 32 ms for VS Code,
but VS Code's roughly 22–37 ms range overlaps ***FLASH***'s roughly 27 ms observations.
***FLASH*** did not win every individual run. Both small-file cursor timings were far
below a millisecond per automated command on average, but these are not measured
physical keystrokes. All final observations and their ranges are preserved;
only favorable observations were not selected.

***FLASH*** disables expensive features above 50,000 lines. Its 60,000-line result is
therefore **protected-mode behavior**, not feature-equivalent syntax/analysis
work against VS Code's default large-file handling. We did not isolate individual
features, match rendering frames, or measure long-session stability, real typing,
LSP indexing, debug sessions, extensions, batteries, or user-customized VS Code.

**This is not a VS Code Remote SSH server-resource comparison.** With Remote SSH,
the GUI runs on the local PC while remote services run on the server. Desktop
RSS here must not be presented as memory used on that remote server. The earlier
***FLASH***/Package-based Neovim/Plugin-free Vim reports and this GUI experiment use different protocols; compare
within a report, not absolute timing values across reports.
