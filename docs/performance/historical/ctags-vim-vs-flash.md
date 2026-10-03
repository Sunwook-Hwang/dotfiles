# Ctags mode: Vim vs FLASH

[English](ctags-vim-vs-flash.md) | [한국어](ctags-vim-vs-flash.ko.md)

This compares the repository's **Vim configuration (`vim/.vimrc`)** against
**FLASH**, with FLASH's LSP disabled so both use Universal Ctags for `gd`.
No configuration code was changed for this comparison. These results describe
this snapshot, not Vim and Neovim in general.

**There is no across-the-board winner in ctags mode.** On the 2,000-line fixture,
Vim had lower configuration evaluation, cursor/redraw, and edit/redraw costs.
FLASH had faster cold and ready-index `gd`, faster window switching, and lower
OS-reported peak RSS. With large-file restrictions active, FLASH also had lower
cursor, editing and window-switching costs on the 60,000-line fixture.

For ctags-only work dominated by ordinary-file editing, **Vim is a reasonable
choice**. For memory constraints, frequent definition jumps or splits, **FLASH
remains a strong choice** in this measurement. The warm-jump difference is under
1 ms here; it should not be marketed as a dramatic perceptual advantage.
Both are more useful choices than a blanket “FLASH always beats Vim” claim.

## Environment and fairness

- Date: 2026-09-28; configuration revision `a3fdb8728b890eaeb345f0fb7bf57ab813ed2114`.
- Apple M4 Mac mini, 10 cores, 16 GB RAM; macOS 27.0 (26A428), arm64.
- Vim **9.2**, patches 1–1100, Homebrew Huge terminal build; not a Vim 9.0 measurement.
- Neovim **0.12.5**, Release; Universal Ctags **6.2.1** for both.
- Same 120 × 40 PTY, `TERM=xterm-256color`, UTF-8 locale, same working directory.
  Both editors run their regular terminal UI; output is continuously drained.
  No physical terminal emulator or SSH connection is involved. Terminal queries
  receive no replies, so the startup marker includes terminal-negotiation waits.
  It is not used to rank real terminal application launch speed.
- Seven fresh processes for each profile and each of two fixtures: **28 launches**.
  The execution order alternates. No swap or ShaDa/viminfo; fresh data/state/cache
  directories and managed tag indexes per process. OS caches are not flushed.
- Both retain their defaults and the `retrobox` theme. LSP is disabled before
  loading FLASH; no formatter runs. Both are package-free configurations.
- The same sources and ctags executable are used. Each configuration builds its
  own managed index through its real `gd` implementation; no prebuilt tag file
  bypasses that path.

The previous [pvi vs FLASH report](no-pack-speedmode.md) used an embedded virtual
UI and different workloads. **Do not compare absolute numbers between reports.**

## Results

Each cell is **median (minimum–maximum)** across seven process runs. Lower costs
are better. Warm `gd` uses the median of 20 lookups within each process, then the
median and range of those seven medians. This keeps process runs equally weighted.
Peak RSS is the OS-reported high-water mark from `wait4`, converted from macOS
bytes to MiB. It is not the settled RSS metric in the earlier report and is not
aggregate memory for the entire process tree.

### source_2k

| Metric                            |                  vimrc |                   FLASH |
| --------------------------------- | ---------------------: | ---------------------: |
| Configuration evaluation (ms)     |      7.10 (5.28–10.34) |    16.29 (12.04–19.07) |
| PTY startup marker (ms)           |    45.47 (41.22–74.05) | 239.09 (222.09–255.18) |
| First gd, including indexing (ms) |    82.96 (79.86–93.58) |    61.38 (55.51–65.02) |
| Ready-index gd (ms)               |       2.66 (2.61–2.84) |       1.76 (1.72–1.82) |
| 600 cursor moves + redraw (ms)    | 295.18 (290.96–300.20) | 388.00 (386.64–391.42) |
| 100 line edits + redraw (ms)      |    77.97 (77.23–78.73) | 111.36 (110.11–111.98) |
| 200 window switches + redraw (ms) | 213.38 (209.88–215.33) | 155.60 (154.06–156.02) |
| Peak RSS (MiB)                    |    49.34 (49.25–49.38) |    21.55 (21.16–21.61) |

### large_60k

| Metric                            |               vimrc |                   FLASH |
| --------------------------------- | ------------------: | ---------------------: |
| Configuration evaluation (ms)     |    8.60 (7.17–9.65) |    16.49 (15.35–17.53) |
| PTY startup marker (ms)           | 57.13 (47.78–64.32) | 244.87 (232.94–255.63) |
| 600 cursor moves + redraw (ms)    | 45.75 (43.86–46.94) |    37.45 (35.42–38.54) |
| 100 line edits + redraw (ms)      | 12.91 (12.78–13.08) |    11.44 (11.27–11.63) |
| 200 window switches + redraw (ms) | 31.30 (31.00–31.74) |    23.69 (23.50–24.34) |
| Peak RSS (MiB)                    | 42.39 (42.34–42.42) |    19.39 (19.19–19.44) |

## Fixtures and exact protocol

The ordinary fixture is a generated Python project: 100 modules, each containing
10 unique functions, plus a 2,000-line `main.py`. Each module `module_III.py`
contains three-line blocks: `def function_III_JJJ(value=0):`, four spaces plus
`return value + J`, then a blank line. I ranges from 0–99 and J from 0–9;
identifiers are zero-padded to three digits. `main.py` starts with
`function_099_009()` followed by `value_N = N` for N=1–1999. Files use LF and a
final newline. The project has a fresh Git repository and untracked sources,
so indexing exercises the configurations' Git file enumeration too.

The large fixture is 60,000 lines of `value_N = N`, N=0–59999, outside that Git
project. It is intentionally protected by the large-buffer policy. `gd` is not
attempted there: it would measure disabled functionality rather than ctags speed.

A thin wrapper times `source`/`dofile` of the real configuration. This isolates
configuration evaluation, not all subsequent runtime plugins, file opening, or
terminal startup. After an initial exploratory comparison, this metric was added
and the complete 28-run experiment was repeated. Only the final run set appears
in the tables and raw data.

Each process loads the same Vimscript measurement driver after its configuration:

1. On `VimEnter`, a zero-delay timer requests `redraw!` and writes a readiness
   marker. Startup is measured in the parent from process creation to observing
   that marker with a 1 ms polling interval. This is not full background-task
   completion or time until a person sees terminal pixels.
2. After 500 ms, record line count, theme, large-buffer flag and, for FLASH, LSP
   client count. On ordinary source, invoke the actual mapped `gd` with
   `feedkeys('gd', 'xt')`. Wait in 1 ms sleeps for the target file, verify the
   declaration text, and redraw. **Cold `gd`** includes index creation, lookup,
   asynchronous callback delivery, opening the destination and redraw.
3. Return to `main.py` and repeat 20 times with the ready index. Time only each
   `gd` and target redraw; exclude the explicit return to the source. Every
   lookup must reach `module_099.py`, `def function_099_009(...)`.
4. On the original buffer, move to lines 1–600, explicitly dispatch `CursorMoved`
   and redraw each time. Then replace lines 2–101 with `# benchmark edit N`,
   dispatching `TextChanged` and redrawing on each of 100 iterations.
5. Vertically split the same buffer and switch between the windows 200 times,
   redrawing each time. These three loops run synchronously in Vimscript in both
   editors, so not all delayed callbacks finish inside their timing intervals.
6. Record `v:errmsg`, exit without saving, and collect process-exit resource
   accounting. Peak RSS covers startup, tag work (ordinary source), editing and
   shutdown. The raw total CPU accounting is not used as an isolated measure of
   interactive editing or presented as aggregate process-tree CPU usage.

Results, versions, individual warm lookups, exit codes and validation counts
are retained in [the raw data](ctags-vim-vs-flash-results.json).

## Interpretation and limits

Ctags is a saved-source symbol index. It does not provide LSP type analysis,
diagnostics, semantic rename or unsaved-source accuracy. Both profiles provide
useful native editing tools, but their implementations and features are not
identical. A ctags comparison does not imply full functional equivalence.

The synthetic fixtures do not model a huge monorepo, slow network filesystem,
ambiguous/multiple definitions, all programming languages, or long editing
sessions. The large-file comparison is **restricted-mode performance**, not
full-featured processing of 60,000 lines. Peak memory on that fixture omits tag
indexing, whereas ordinary-source peak memory includes it.

These measurements were made on a modern Mac, not the user's older Red Hat
server. The Vim version, terminal, filesystem and ctags availability on that
server can change the result. Neither report establishes a universal winner.
Use the measured tradeoffs below alongside which editor and features the server
actually supports.
