# FLASH vs Package-based Neovim — matched ty LSP environment

[English](flash-package-based-neovim-lsp.md) | [한국어](flash-package-based-neovim-lsp.ko.md)

Both profiles support LSP. We matched **the ty executable/version, Python
environment, project, client capability declarations, server settings and change
notification debounce**. Actual attachment hooks, UI and `gd` mappings remain.
This is separate from the no-LSP baseline, not feature parity across all workflows
or a claim about every language server.

Seven independent processes per profile, **14 runs** total. Values are medians
(minimum–maximum); repeated tasks use each process's median. Percent changes use
unrounded medians with Package-based Neovim as baseline; negative means lower cost, not an overall
editor speed gain.

| Measurement                                 |                  FLASH |   Package-based Neovim | FLASH change vs Package-based Neovim |
| ------------------------------------------- | ---------------------: | ---------------------: | -----------------------------------: |
| First timed definition request (ms)         |       0.84 (0.25–1.72) |       0.91 (0.28–1.40) |                                -7.6% |
| Repeated definition request (ms)            |       0.14 (0.05–0.22) |       0.15 (0.07–0.17) |                                -3.1% |
| Completion response (ms)                    |       4.17 (4.03–4.62) |       4.42 (4.21–4.67) |                                -5.7% |
| Actual mapped gd after warmup (ms)          |       1.00 (0.98–1.08) |       7.04 (6.84–7.41) |                               -85.8% |
| Saved edit → undefined-name diagnostic (ms) |      9.03 (8.54–16.27) |     10.82 (8.34–19.54) |                               -16.5% |
| Saved correction → diagnostic cleared (ms)  |      8.63 (8.12–10.72) |      8.85 (8.01–11.90) |                                -2.5% |
| 600 cursor moves + redraw (ms)              | 419.87 (416.34–428.15) | 553.70 (548.85–575.67) |                               -24.2% |
| 200 window switches + redraw (ms)           | 273.45 (265.76–274.95) | 310.82 (309.26–319.63) |                               -12.0% |
| Editor sampled RSS (MiB)                    |    32.92 (31.38–34.03) |    43.67 (40.05–44.36) |                               -24.6% |
| ty sampled RSS (MiB)                        |    74.72 (74.33–76.33) |    75.25 (74.39–76.20) |                                -0.7% |
| Editor + ty sampled RSS (MiB)               | 107.70 (107.09–108.91) | 118.39 (115.30–120.56) |                                -9.0% |
| Editor peak RSS over entire run (MiB)       |    35.19 (34.78–36.88) |    45.52 (41.62–46.03) |                               -22.7% |

## Method and validation

2026-10-03, configuration `aa2cf6b`, Mac mini M4, 16 GiB, macOS 27.0.1,
Neovim 0.12.5, ty 0.0.84 and Python 3.14.8, in a 120×40 PTY. The Git project
contains 100 Python modules, 1,000 typed functions and a 2,000-line main.py,
without third-party dependencies. Profile order alternates; runs are sequential.

The benchmark explicitly normalizes the ty command, Python executable, client
capabilities, settings and `debounce_text_changes=150`, enabling no other servers.
Actual LspAttach hooks, diagnostic handlers, semantic highlighting and mappings
remain. Both use incremental sync. Every run must have exactly one attached ty
client; server capabilities, client capabilities, settings and commands must match
across all runs. This is a controlled comparison, not untouched default settings.

After the first timed definition request, 20 definition and 20 completion requests
use the same native client API. Completion must return candidates; popup rendering
is excluded. Actual mapped `gd` runs once then 20 times after warmup, with all jumps
validated at the same function. Returning to the source is outside timing.
Analysis can run before the first timed request; that value is not cold indexing.

Five cycles introduce and save an undefined name, wait for its diagnostic, restore
and save valid code, then wait for all diagnostics to clear. The same ty instance
must stay attached without restart. All 294 mapped jumps, 280 repeated definition
requests, 280 completion requests and 70 diagnostic error/clear cycles passed.

Existing cursor/edit/window-switch workloads then run with LSP attached. Their
synchronous loops may leave delayed server work outside the timed interval, so they
are not LSP throughput or physical typing latency. Normal exit, empty errors,
expected edits, final cursor and window count are validated.

## Memory and interpretation

After diagnostic cycles, one `ps` snapshot records editor and child ty RSS
separately. Their sum double-counts shared pages; it is not unique physical memory,
a peak, or a long-term settled average. The separate editor peak is the entire
process high-water mark, including subsequent workloads, and excludes ty.

Differences between direct definition requests and mapped gd include dispatch,
UI and event handling. No individual plugin's cause is isolated. Diagnostic values
and variation do not establish a consistently faster profile. SSH, NFS, weak Linux
servers, long editing sessions, other language servers and collaboration are untested.

Editor configuration is unchanged. State/cache/session/undo are isolated; packages
reuse installed-version copies and the lockfile. All copied package Git revisions
match the installed versions after measurement. Only the temporary project is saved.

[Raw data / 원본 데이터](flash-package-based-neovim-lsp-results.json) · [Performance index](README.md)
