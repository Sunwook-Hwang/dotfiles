# ***FLASH*** vs Package-based Neovim — matched ty LSP environment

[English](flash-package-based-neovim-lsp.md) | [한국어](flash-package-based-neovim-lsp.ko.md)

2026-10-13, configuration `b9b2102`, Mac mini M4 · 16 GiB · macOS 27.0.1,
Neovim 0.12.6 · ty 0.0.86 · Python 3.15.0.

Both profiles use **the same ty executable, Python environment, project, client
capabilities, server settings and `debounce_text_changes=150`**. Each profile retains
its actual attachment hooks, default theme, UI and `gd` mapping. This matches the
tested LSP tasks, not every feature or default setting.

Seven independent processes per profile, **14 runs** total, alternating order and
running sequentially. Values are medians (minimum–maximum); repeated requests use
each process's median. Bold marks the lower observed median, not statistical
significance. Percentages use unrounded medians with Package-based Neovim as baseline;
negative means lower cost, not an overall editor speed gain.

| Measurement | ***FLASH*** | Package-based Neovim | ***FLASH*** change vs Package-based Neovim |
| --- | ---: | ---: | ---: |
| First timed definition request (ms) | 0.84 (0.29–1.34) | **0.79** (0.32–1.37) | +6.8% |
| Repeated definition request (ms) | 0.16 (0.08–0.19) | **0.16** (0.06–0.19) | +1.2% |
| Completion response, excluding popup (ms) | **4.06** (3.92–4.67) | 4.26 (4.17–4.45) | -4.6% |
| Actual mapped gd after warmup (ms) | **0.97** (0.93–1.03) | 7.62 (7.17–7.77) | -87.3% |
| Saved edit → undefined-name diagnostic (ms) | **9.00** (7.64–9.76) | 9.30 (7.85–10.84) | -3.3% |
| Saved correction → diagnostic cleared (ms) | **9.99** (7.56–17.83) | 10.75 (8.31–11.82) | -7.1% |
| 600 cursor moves + redraw (ms) | **403.90** (402.49–426.53) | 536.03 (526.94–541.45) | -24.6% |
| 100 edits + redraw (ms) | **112.13** (111.16–117.70) | 119.89 (117.98–126.03) | -6.5% |
| 200 window switches + redraw (ms) | **264.50** (263.14–274.84) | 309.35 (303.47–310.04) | -14.5% |
| 100 timer-driven cursor moves (ms) | **268.10** (258.86–279.25) | 285.35 (283.08–295.07) | -6.0% |
| Editor sampled RSS (MiB) | **35.66** (33.44–37.48) | 43.56 (42.84–46.27) | -18.1% |
| ty sampled RSS (MiB) | 70.61 (69.28–71.28) | **70.47** (69.97–70.75) | +0.2% |
| Editor + ty sampled RSS (MiB) | **105.42** (103.95–108.17) | 114.02 (113.28–117.02) | -7.5% |
| Editor peak RSS over entire run (MiB) | **38.39** (36.81–39.83) | 44.81 (43.50–46.92) | -14.3% |

## Workload and validation

- Same fixture as the earlier comparison: a Git project with 100 Python modules,
  1,000 typed functions and a 2,000-line main.py, in a 120×40 PTY.
- Exactly one ty client per run, identical client/server capabilities, settings,
  command and incremental synchronization. No other language server is enabled.
- **294 actual mapped `gd` jumps**, 280 repeated definition requests, 280 completion
  requests and **70 diagnostic error/clear cycles** passed without restarting ty.
  Every jump reaches the expected function; every completion response contains candidates.
- Each diagnostic cycle saves an undefined name, waits for its diagnostic, then
  saves valid code and waits for diagnostics to clear. Cursor, edit and window
  workloads verify edits, final cursor, window count, normal exit and no editor error.
- State, caches, sessions and undo are isolated. The 19 installed packages are
  copied with the lockfile; their Git revisions match before and after measurement.
  No editor or plugin code is changed for the experiment.

## Interpretation

Direct definition requests are nearly identical. Actual `gd` includes each profile's
dispatch, UI and redraw work; this experiment does not isolate an individual plugin.
Completion and diagnostic response ranges overlap. Synchronous cursor/edit/window
loops may leave delayed LSP work outside their timed interval; the timer-driven
workload also includes timer scheduling. Neither measures physical typing latency.

RSS is one `ps` snapshot after diagnostic cycles. The combined value sums editor and
ty RSS, including shared pages; it is not unique physical memory or a long-term
average. The separate peak is the editor process's high-water mark and excludes ty.

The raw data retains startup markers, but this protocol does not answer terminal
queries, so those markers are not ranked as startup speed. SSH, NFS, slow Linux
servers, long sessions and collaboration were not measured.

The earlier 2026-10-03 medians are retained in the raw data's `previous_measurement`.
Neovim, ty, Python, configuration and package revisions have changed; their differences
do not isolate the effect of the ten pvi optimization rounds.

[Raw data](flash-package-based-neovim-lsp-results.json) · [Performance index](README.md)
