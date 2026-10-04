# Performance by use case — ***FLASH***, Package-based Neovim and Plugin-free Vim

[English](editor-baseline.md) | [한국어](editor-baseline.ko.md)

These profiles differ in capabilities and purpose; there is no overall winner.
This reorganizes the existing 63 launches, rather than introducing new measurements.
Values are **seven-run medians (minimum–maximum)**.

## Where comparison conditions match

- **Ctags comparison completed:** Plugin-free Vim has no LSP support, so ***FLASH***'s LSP was
  disabled. Both used the same project, ctags tool and definition-navigation task,
  preserving each profile's actual implementation.
- **Matched ty LSP tasks now measured separately:** ***FLASH*** and Package-based Neovim use the same ty,
  Python environment, project, client capability declarations, settings and
  debounce in 14 additional runs. Attachment, definition navigation, completion
  and diagnostic updates are validated in the [LSP report](flash-package-based-neovim-lsp.md).
  This is not parity across all languages/features. This page's 63-run baseline
  remains LSP-disabled.

## ***FLASH*** and Package-based Neovim: common editing costs

Both use Neovim's native LSP client. ***FLASH*** implements features without external Lua
plugins, whereas Package-based Neovim uses plugins. These measurements are an **LSP-disabled baseline**.
Completion, outline, explorer and formatting workflows were not benchmarked, so
these results do not establish costs at feature parity or rank real development workflows.

On the 2,000-line fixture, ***FLASH*** used **24.0% less peak RSS**, **21.4% less cursor
movement time**, and **12.3% less window switching time** than Package-based Neovim. On the tracked
Git fixture, those reductions were **20.8%**, **26.7%**, and **26.3%**, respectively.
These are differences in the measured operations, not overall speed gains.

Percentages use Package-based Neovim as the baseline: `(result / baseline − 1) × 100`. Negative values
mean less time or memory. PTY readiness measurements are separated from the main
tables; the reference section at the end links to the startup rerun.

### source_2k

| Measurement                       |                  ***FLASH*** |   Package-based Neovim | ***FLASH*** change vs Package-based Neovim |
| --------------------------------- | ---------------------: | ---------------------: | -----------------------------------: |
| Configuration evaluation (ms)     |    27.08 (22.60–28.33) |    56.29 (52.64–61.98) |                               -51.9% |
| 600 cursor moves + redraw (ms)    | 471.76 (458.08–491.50) | 600.06 (583.16–660.56) |                               -21.4% |
| 100 edits + redraw (ms)           | 117.19 (115.30–125.11) | 124.16 (122.58–154.05) |                                -5.6% |
| 200 window switches + redraw (ms) | 270.80 (266.40–290.58) | 308.86 (307.46–334.14) |                               -12.3% |
| 100 event-loop moves (ms)         | 230.55 (207.26–239.00) | 284.46 (268.18–287.44) |                               -19.0% |
| RSS at readiness (MiB)            |    10.12 (10.09–10.14) |    10.12 (10.12–10.16) |                                +0.0% |
| Peak RSS (MiB)                    |    18.41 (18.36–18.56) |    24.20 (23.89–24.38) |                               -24.0% |

### tracked_git

| Measurement                       |                  ***FLASH*** |      Package-based Neovim | ***FLASH*** change vs Package-based Neovim |
| --------------------------------- | ---------------------: | ------------------------: | -----------------------------------: |
| Configuration evaluation (ms)     |    26.47 (23.69–34.21) |       54.66 (42.12–55.58) |                               -51.6% |
| 600 cursor moves + redraw (ms)    | 766.07 (662.11–781.19) | 1044.84 (1007.72–1086.77) |                               -26.7% |
| 100 edits + redraw (ms)           | 139.07 (100.05–140.37) |    163.33 (160.04–171.69) |                               -14.9% |
| 200 window switches + redraw (ms) | 321.78 (312.93–326.17) |    436.39 (431.56–446.04) |                               -26.3% |
| 100 event-loop moves (ms)         | 231.70 (223.82–237.96) |    299.91 (286.38–311.55) |                               -22.7% |
| RSS at readiness (MiB)            |    10.16 (10.14–10.19) |       10.17 (10.14–10.20) |                                -0.2% |
| Peak RSS (MiB)                    |    25.59 (24.55–25.70) |       32.33 (32.09–33.06) |                               -20.8% |

### large_60k

**Protected large-file mode.** Every profile activates its protective policy and
reduces functionality. Feature parity under these policies was not independently
verified. ***FLASH*** had lower synchronous operation costs; Package-based Neovim had the shorter timer
traversal. Do not compare this directly with ordinary files or infer that larger
files are intrinsically faster.

| Measurement                       |                  ***FLASH*** |   Package-based Neovim | ***FLASH*** change vs Package-based Neovim |
| --------------------------------- | ---------------------: | ---------------------: | -----------------------------------: |
| Configuration evaluation (ms)     |    26.09 (22.49–29.41) |    54.30 (51.22–57.49) |                               -51.9% |
| 600 cursor moves + redraw (ms)    |  100.04 (92.93–101.15) | 205.36 (191.78–236.75) |                               -51.3% |
| 100 edits + redraw (ms)           |    10.41 (10.11–10.81) |    13.53 (12.99–14.76) |                               -23.1% |
| 200 window switches + redraw (ms) |    32.87 (32.59–34.57) |    58.02 (55.45–59.55) |                               -43.3% |
| 100 event-loop moves (ms)         | 116.51 (111.48–126.30) | 107.30 (104.21–112.06) |                                +8.6% |
| RSS at readiness (MiB)            |    10.11 (10.08–10.14) |    10.14 (10.08–10.14) |                                -0.3% |
| Peak RSS (MiB)                    |    19.59 (19.52–19.72) |    26.03 (25.67–26.56) |                               -24.7% |

## ***FLASH*** and Plugin-free Vim: matched ctags tasks

See the [separate ctags report](flash-plugin-free-vim-ctags.md) for no-LSP navigation using
the actual `gd` mappings in the same project. ***FLASH*** took 18.4% less time for the
first lookup and 32.6% less for indexed lookups. The indexed difference is only
0.83 ms; do not translate it into a noticeable responsiveness advantage. This
does not imply parity in every other feature.

## Plugin-free Vim: common editing reference values

Vim has a different build and feature set from Neovim. These are reference costs,
not an overall ranking against LSP-enabled workflows or memory claims for other builds.

| Measurement                       |              source_2k |            tracked_git |  large_60k (protected) |
| --------------------------------- | ---------------------: | ---------------------: | ---------------------: |
| Configuration evaluation (ms)     |      8.25 (4.90–11.70) |       8.60 (7.56–8.99) |       9.18 (5.55–9.55) |
| 600 cursor moves + redraw (ms)    | 422.72 (417.10–425.82) | 693.12 (670.16–695.93) | 131.04 (115.61–132.82) |
| 100 edits + redraw (ms)           |    95.73 (94.40–98.41) | 131.82 (130.61–132.97) |    20.38 (19.92–20.59) |
| 200 window switches + redraw (ms) | 371.47 (368.44–376.20) | 523.43 (518.27–531.28) |    81.89 (81.75–82.36) |
| 100 event-loop moves (ms)         | 274.18 (268.17–279.55) | 323.64 (305.57–327.40) | 152.33 (150.36–152.91) |
| RSS at readiness (MiB)            |    42.77 (42.73–42.81) |    44.36 (44.31–44.41) |    42.52 (42.47–42.64) |
| Peak RSS (MiB)                    |    43.81 (43.75–43.88) |    46.02 (45.94–46.11) |    43.11 (43.09–43.25) |

## Method and limitations

Measured 2026-10-03 at `584ff5a7c6b62386eb2cb7d83b324cbfdcafc83d` on Mac16,10, 10 CPU cores,
16 GiB RAM, macOS-27.0.1-arm64-arm-64bit-Mach-O. Neovim 0.12.5,
Vim 9.2 patches 1–1150. Seven independent processes per profile and fixture:
**63 measured launches**. Each table shows median (minimum–maximum); lower costs
are better. The raw JSON retains every observation, validation and package revision.

All profiles use their actual configuration in the same 120 × 40 PTY with UTF-8
and `TERM=xterm-256color`. Normal themes remain: ***FLASH*** retrobox, Package-based Neovim catppuccin,
and Plugin-free Vim's configured theme. LSP startup is disabled before loading both Neovim
profiles; no formatter, outline, explorer, AI or collaboration session is invoked.
Installed plugin directories are copied once using APFS clonefile; their common
parent is linked into temporary data directories, with the installed lockfile
copied too. Individual plugin directories are real directories, as vim.pack
requires. Package revisions, including Peerpad, are recorded in JSON.
State, cache, session and undo paths are isolated. No user files are saved and no
packages are installed or updated by the measurement harness. Filesystem caches
are not flushed. Profile order rotates on each repetition; runs are sequential.

Fixtures are a 2,000-line Python file, a 60,000-line Python file (both generated
`value_N = N` lines, outside Git), and the actual tracked ***FLASH*** `lua/git.lua`.
Hashes, sizes and line counts are in the raw results. The large file must activate
the protective buffer policy in every profile; ordinary fixtures must not.

Configuration evaluation times source/dofile of the configuration. PTY readiness
runs from process creation until a zero-delay VimEnter timer requests redraw and
writes a marker. The parent drains PTY output and observes it with up to 5 ms
polling delay. Terminal queries receive no emulator response: **startup markers
include terminal negotiation and are not human-visible launch speed rankings**.

After 500 ms: move through 600 lines, explicitly dispatch CursorMoved and redraw;
replace 100 lines, dispatch TextChanged and redraw; split the same buffer and
switch windows 200 times with redraw. Those loops run synchronously in the same
Vimscript driver for every editor. Delayed tasks can complete outside burst times.
Next, 100 timer-driven cursor moves yield to the event loop between redraws.
That wall time includes timer scheduling and natural cursor-event delivery.
It is not physical key-to-screen latency or a sustained typing benchmark.

Ready RSS is sampled immediately after the marker, before the 500 ms settling
interval. Peak RSS is the editor process high-water mark from macOS wait4, not
settled memory, Lua heap, GUI memory or aggregate process-tree usage. Child
processes such as Git/ctags are excluded. Total CPU accounting in JSON covers
startup, workloads and shutdown; it is not isolated idle or cursor CPU time.
An initial isolated run set used individual plugin symlinks and omitted the
lockfile. vim.pack treated those symlinks as bad installations and repaired them.
That invalid setup is retained in unlocked-startup-exploratory-results.json,
explicitly excluded from the final dataset; its revision metadata is not verified.
The final prepared template must have the same Git revisions before and after
all runs, and its package directory set must remain unchanged.
All measured runs must exit normally with empty v:errmsg, zero LSP clients,
validated edits, cursor line 700, and two source windows. Pilot runs are excluded.

Do not market historical ratios as current results: the older Package-based Neovim/***FLASH*** report used
an embedded Neovim UI, synthetic Lua files and different revisions. This study
uses PTYs and Python fixtures. It does not isolate why any individual plugin or
feature is expensive, or prove that an old bottleneck has been eliminated.

For a weak server, weigh resource overhead and the measured workflows against
needed features. Plugin-free Vim has no LSP; the LSP-disabled baseline does not establish
feature equivalence. Real language servers, NFS, SSH, long sessions and physical
terminal rendering need separate target-server measurements.

[Ctags navigation comparison](flash-plugin-free-vim-ctags.md) · [Raw data](editor-baseline-results.json)

## Reference: startup timing measurement

See the [startup measurement](startup-cause.md) for all three configurations ([raw data](startup-cause-results.json)). Editing and memory results on this page are from a separate experiment.
