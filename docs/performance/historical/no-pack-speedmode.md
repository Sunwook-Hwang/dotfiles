# no-pack-speedmode

[English](no-pack-speedmode.md) | [한국어](no-pack-speedmode.ko.md)

**Native Neovim. No plugin packages. Built for constrained machines.**

`FLASH` provides a dashboard, file tree, fuzzy pickers, Git signs, LSP integration,
completion, formatting, outline, terminal, and statusline using Neovim's native
APIs and installed command-line tools. `no-pack-speedmode` is the name of this
performance report, not a new command, toggle, or stripped-down configuration.

This report compares this repository's actual `pvi` and `FLASH` configurations.
It does not compare all plugin-based and plugin-free Neovim configurations.
Optional language servers, formatters, Git, and search tools remain external
executables; “no pack” does not mean zero dependencies for every feature.

## Measured snapshot

- Configuration revision: `a3fdb8728b890eaeb345f0fb7bf57ab813ed2114`.
- Date: 2026-09-28.
- Machine: Mac mini, Apple M4, 10 CPU cores, 16 GB RAM.
- OS: macOS 27.0 (26A428), arm64.
- Editor: Neovim 0.12.5 Release, LuaJIT 2.1.1788856981.
- Display: embedded RPC with a headless, RGB, 120 × 40 virtual UI.
- Seven fresh processes per profile per fixture, **42 measured launches** total.
- Profile order alternates each repetition. Both profiles use the same fixture.
- Each process receives fresh state/cache directories, no swap, and no ShaDa.
  Installed packages/data are reused; the OS filesystem cache is not flushed.
- `NVIM_APPNAME` is set to `nvim` or `nvim-nopack` respectively; each profile's
  `init.lua` is loaded directly. Both processes start in the repository root.
- LSP activation is disabled for both profiles before configuration loading.
  No formatter is invoked. This isolates editor work from external language tools.
- Normal default UI settings are retained, including different themes:
  `rose-pine` for pvi, `retrobox` for FLASH. Sticky Scroll, smooth scrolling, and
  inline blame are off; outline and explorer are not opened.

Installed package revisions, fixture hashes, all individual observations, and
summary statistics are in the [raw results](no-pack-speedmode-results.json).
This replaces the earlier informal five-run comparison as the documented dataset.

## Results

Every cell is **median (minimum–maximum)** across seven runs. Lower is better
for these costs. RSS is process resident memory, not Lua heap size; it excludes
child processes and is not a peak-memory measurement.

### source_2k — 2,000 lines

| Metric                     |                    pvi |                   FLASH |
| -------------------------- | ---------------------: | ---------------------: |
| Startup (ms)               |   89.76 (64.13–100.04) |    65.83 (38.52–69.89) |
| 600 cursor moves (ms)      | 645.64 (632.65–744.81) | 375.39 (363.75–402.10) |
| 100 line replacements (ms) | 124.46 (120.80–126.02) |    92.77 (90.27–94.73) |
| 200 window switches (ms)   | 312.71 (303.95–321.59) | 120.67 (115.29–126.77) |
| 100 RPC cursor moves (ms)  | 125.70 (122.23–127.37) |    71.21 (67.41–75.46) |
| Settled startup RSS (MiB)  |    13.50 (13.22–13.66) |      9.78 (9.25–10.08) |
| Post-workload RSS (MiB)    |    18.67 (18.28–19.28) |    13.00 (12.61–13.73) |
| CPU during 1 s idle (ms)   |       1.91 (1.51–2.16) |       0.19 (0.07–0.26) |

### large_60k — 60,000 lines

| Metric                     |                       pvi |                FLASH |
| -------------------------- | ------------------------: | ------------------: |
| Startup (ms)               |     104.58 (98.34–116.53) | 67.57 (61.89–78.84) |
| 600 cursor moves (ms)      | 2703.87 (2547.34–2851.49) | 68.58 (63.02–72.38) |
| 100 line replacements (ms) |       75.32 (71.05–80.03) | 10.91 (10.82–11.32) |
| 200 window switches (ms)   |    301.63 (286.35–329.94) | 20.68 (20.21–21.52) |
| 100 RPC cursor moves (ms)  |   953.04 (889.76–1028.28) | 16.14 (16.04–17.33) |
| Settled startup RSS (MiB)  |       45.44 (45.19–45.63) |    9.13 (8.92–9.27) |
| Post-workload RSS (MiB)    |       51.00 (50.61–51.22) | 11.66 (11.33–11.70) |
| CPU during 1 s idle (ms)   |          1.45 (1.15–2.16) |    0.23 (0.17–0.35) |

### tracked_git — 994 lines

| Metric                     |                      pvi |                   FLASH |
| -------------------------- | -----------------------: | ---------------------: |
| Startup (ms)               |    104.12 (92.41–123.86) |    65.40 (58.02–70.39) |
| 600 cursor moves (ms)      | 1046.23 (963.84–1274.20) | 798.21 (758.83–888.88) |
| 100 line replacements (ms) |   177.68 (132.32–198.42) | 155.75 (144.72–165.68) |
| 200 window switches (ms)   |   457.02 (432.07–525.09) | 173.75 (169.67–187.19) |
| 100 RPC cursor moves (ms)  |   161.88 (156.54–187.74) | 115.54 (101.08–138.93) |
| Settled startup RSS (MiB)  |      15.06 (14.73–16.00) |    10.48 (10.30–11.14) |
| Post-workload RSS (MiB)    |      23.20 (22.48–23.97) |    16.38 (16.13–16.81) |
| CPU during 1 s idle (ms)   |         3.83 (3.05–4.51) |       0.20 (0.13–0.34) |

## Large-file follow-up

All 42 runs had an empty `vim.v.errmsg` and zero LSP clients. Both profiles
reported a restricted buffer for the 60,000-line fixture; the other fixtures
remained unrestricted.

A separate, single-run exploratory probe reproduced the large-file gap. Both
profiles already had `syntax=OFF`, manual folds, and cursorline/cursorcolumn off.
Clearing pvi's statuscolumn did not remove the gap. Syntax highlighting or the
status column alone therefore does not explain it. The root cause has not been
isolated, and this extreme ratio is deliberately not the README headline.
Probe phases ran sequentially in one process per profile, so warm-up effects
also apply. Probe values are included in the raw data but not pooled into the
seven-run summaries.

## Workloads and timing boundaries

Three fixtures are used: a generated 2,000-line Lua file, a generated 60,000-line
Lua file, and the Git-tracked `nvim-nopack/.config/nvim-nopack/lua/git.lua` at the
recorded revision. Generated files live outside Git. Their four-line block is
`local function sample_N(value)`, a tab-indented `if value then`, a two-tab
`return value + N`, and a tab-indented `end end`, with N starting at one.
Blocks are repeated 500 or 15,000 times, with LF and a final newline.
These are synthetic text fixtures, not executed Lua programs.

Each child process performs the following sequence:

1. **Startup:** time from process spawn through UI attachment and completion of
   the first explicitly requested `redraw!`. This is not completion of every
   scheduled plugin or background task.
2. Wait 500 ms, then record RSS using `vim.uv.resident_set_memory()`, line count,
   theme, LSP client count, and the shared buffer policy's restriction state.
3. **Cursor burst:** move to lines 1–600, column zero; explicitly dispatch
   `CursorMoved` and redraw at each step inside one Lua RPC.
4. **Edit burst:** replace zero-based lines 1–100 with `-- benchmark edit N`,
   explicitly dispatch `TextChanged` and redraw each time inside one Lua RPC.
   Files are never saved. This does not model Insert-mode typing or completion.
5. Open one vertical split of the same buffer. **Window switching:** alternate
   focus between the two windows 200 times, redrawing at each step in one RPC.
6. **Event-loop traversal:** move through lines 601–700 using 100 separate RPCs,
   each dispatching `CursorMoved` and redrawing. Unlike the burst, these calls
   allow scheduled callbacks to run between requests. Timings include RPC overhead;
   timers whose delay exceeds the workload duration need not complete.
7. Wait 500 ms. Measure user + system CPU time via `vim.uv.getrusage()` over a
   one-second idle interval, then record RSS again. Exit without saving.

The later measurements include state accumulated by the earlier workloads.
They are not independent cold-start microbenchmarks. Git edits can schedule
asynchronous work that completes outside the edit burst. Idle CPU measures the
Neovim process only. UI rendering occurs in a virtual grid, not an actual
terminal emulator, SSH connection, or Neovide GPU window.

## Why FLASH is a useful server option

The implementation has mechanisms that limit work:

- Indentation guides use native `listchars` / `leadmultispace` rather than a Lua
  decoration provider regenerating guides on redraw.
- Git diff computation runs in a worker with one active request and a replaceable
  pending request, so rapid edits do not create an unbounded queue of snapshots.
- Both profiles share the same large-buffer limits: more than 50,000 lines,
  more than 2 MiB, or a line longer than 10,000 bytes. Restriction disables
  expensive features instead of processing every buffer identically.
- Sticky Scroll, smooth scrolling, and inline blame are optional and off by
  default. Native breadcrumbs read cached symbols during cursor movement.
- FLASH does not install plugin packages or parsers. Known optional external
  tools are used only when available, which simplifies disconnected deployment.

These are code observations, not a profiler attribution of each millisecond.
The benchmark compares whole profiles with different capabilities and themes;
no single plugin is proven responsible for the measured differences.

## What this does not establish

This is a **local benchmark, not a weak-server or SSH latency measurement**.
It does not establish a universal speed multiplier, sustained interactive frame
rate, long-session memory stability, or performance across all filetypes.
The 60,000-line case tests protected behavior: fewer editing features are active,
so it is not evidence of full-featured large-file processing speed.

LSP analysis/indexing, completion, formatter execution, explorer rendering,
outline navigation, interactive terminal programs, and large-repository Git
operations have not been benchmarked here. A CPU-heavy language server can
still dominate either configuration. Memory figures omit language servers and
other children. Burst timings do not include all delayed work.

For a slow or disconnected server, start with **FLASH's defaults**. Choose pvi
when its plugin interfaces matter more than their additional baseline cost.
Repeat the same protocol on the target Linux server before publishing claims
about that server. Keep slower or inconclusive cases in any future report, and
record the new configuration and plugin revisions rather than reusing these
numbers after changes.

Related study: [Vim vs FLASH in ctags mode](ctags-vim-vs-flash.md). Vim wins some ordinary-editing workloads; FLASH is not universally faster.

GUI comparison: [FLASH + Neovide vs VS Code](flash-vs-vscode.md), including process-tree RSS and automation caveats.
