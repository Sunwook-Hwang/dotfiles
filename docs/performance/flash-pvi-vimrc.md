# FLASH vs pvi vs vimrc — current configuration

[English](flash-pvi-vimrc.md) | [한국어](flash-pvi-vimrc.ko.md)

This compares these three configured editors, not all Neovim or Vim configurations.
The benchmark measures common editing work with language-server costs removed.

FLASH has the lowest measured peak RSS and split-switching cost in all three
fixtures. Vimrc loads its configuration fastest and has lower ordinary-file
cursor/edit burst costs than FLASH. Pvi is not slowest in every metric: on the
protected 60k fixture its timer-driven cursor traversal is slightly shorter than
FLASH. That interval includes timer scheduling; it is not a typing-speed claim.

## source_2k

| Metric                            |                  FLASH |                    pvi |                  vimrc |
| --------------------------------- | ---------------------: | ---------------------: | ---------------------: |
| Configuration evaluation (ms)     |    27.08 (22.60–28.33) |    56.29 (52.64–61.98) |      8.25 (4.90–11.70) |
| PTY readiness marker (ms)         | 242.97 (228.25–253.27) | 275.44 (265.56–293.92) |    68.61 (58.20–89.15) |
| 600 cursor moves + redraw (ms)    | 471.76 (458.08–491.50) | 600.06 (583.16–660.56) | 422.72 (417.10–425.82) |
| 100 edits + redraw (ms)           | 117.19 (115.30–125.11) | 124.16 (122.58–154.05) |    95.73 (94.40–98.41) |
| 200 window switches + redraw (ms) | 270.80 (266.40–290.58) | 308.86 (307.46–334.14) | 371.47 (368.44–376.20) |
| 100 event-loop moves (ms)         | 230.55 (207.26–239.00) | 284.46 (268.18–287.44) | 274.18 (268.17–279.55) |
| RSS at readiness (MiB)            |    10.12 (10.09–10.14) |    10.12 (10.12–10.16) |    42.77 (42.73–42.81) |
| Peak RSS (MiB)                    |    18.41 (18.36–18.56) |    24.20 (23.89–24.38) |    43.81 (43.75–43.88) |

## large_60k

| Metric                            |                  FLASH |                    pvi |                  vimrc |
| --------------------------------- | ---------------------: | ---------------------: | ---------------------: |
| Configuration evaluation (ms)     |    26.09 (22.49–29.41) |    54.30 (51.22–57.49) |       9.18 (5.55–9.55) |
| PTY readiness marker (ms)         | 236.10 (232.33–246.82) | 275.76 (268.23–292.85) |    61.51 (44.80–66.34) |
| 600 cursor moves + redraw (ms)    |  100.04 (92.93–101.15) | 205.36 (191.78–236.75) | 131.04 (115.61–132.82) |
| 100 edits + redraw (ms)           |    10.41 (10.11–10.81) |    13.53 (12.99–14.76) |    20.38 (19.92–20.59) |
| 200 window switches + redraw (ms) |    32.87 (32.59–34.57) |    58.02 (55.45–59.55) |    81.89 (81.75–82.36) |
| 100 event-loop moves (ms)         | 116.51 (111.48–126.30) | 107.30 (104.21–112.06) | 152.33 (150.36–152.91) |
| RSS at readiness (MiB)            |    10.11 (10.08–10.14) |    10.14 (10.08–10.14) |    42.52 (42.47–42.64) |
| Peak RSS (MiB)                    |    19.59 (19.52–19.72) |    26.03 (25.67–26.56) |    43.11 (43.09–43.25) |

## tracked_git

| Metric                            |                  FLASH |                       pvi |                  vimrc |
| --------------------------------- | ---------------------: | ------------------------: | ---------------------: |
| Configuration evaluation (ms)     |    26.47 (23.69–34.21) |       54.66 (42.12–55.58) |       8.60 (7.56–8.99) |
| PTY readiness marker (ms)         | 194.25 (188.84–202.37) |    239.67 (212.87–242.89) |    62.82 (59.74–72.09) |
| 600 cursor moves + redraw (ms)    | 766.07 (662.11–781.19) | 1044.84 (1007.72–1086.77) | 693.12 (670.16–695.93) |
| 100 edits + redraw (ms)           | 139.07 (100.05–140.37) |    163.33 (160.04–171.69) | 131.82 (130.61–132.97) |
| 200 window switches + redraw (ms) | 321.78 (312.93–326.17) |    436.39 (431.56–446.04) | 523.43 (518.27–531.28) |
| 100 event-loop moves (ms)         | 231.70 (223.82–237.96) |    299.91 (286.38–311.55) | 323.64 (305.57–327.40) |
| RSS at readiness (MiB)            |    10.16 (10.14–10.19) |       10.17 (10.14–10.20) |    44.36 (44.31–44.41) |
| Peak RSS (MiB)                    |    25.59 (24.55–25.70) |       32.33 (32.09–33.06) |    46.02 (45.94–46.11) |

## Method and limitations

Measured 2026-10-03 at `584ff5a7c6b62386eb2cb7d83b324cbfdcafc83d` on Mac16,10, 10 CPU cores,
16 GiB RAM, macOS-27.0.1-arm64-arm-64bit-Mach-O. Neovim 0.12.5,
Vim 9.2 patches 1–1150. Seven independent processes per profile and fixture:
**63 measured launches**. Each table shows median (minimum–maximum); lower costs
are better. The raw JSON retains every observation, validation and package revision.

All profiles use their actual configuration in the same 120 × 40 PTY with UTF-8
and `TERM=xterm-256color`. Normal themes remain: FLASH retrobox, pvi catppuccin,
and vimrc's configured theme. LSP startup is disabled before loading both Neovim
profiles; no formatter, outline, explorer, AI or collaboration session is invoked.
Installed plugin directories are copied once using APFS clonefile; their common
parent is linked into temporary data directories, with the installed lockfile
copied too. Individual plugin directories are real directories, as vim.pack
requires. Package revisions, including Peerpad, are recorded in JSON.
State, cache, session and undo paths are isolated. No user files are saved and no
packages are installed or updated by the measurement harness. Filesystem caches
are not flushed. Profile order rotates on each repetition; runs are sequential.

Fixtures are a 2,000-line Python file, a 60,000-line Python file (both generated
`value_N = N` lines, outside Git), and the actual tracked FLASH `lua/git.lua`.
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

Do not market historical ratios as current results: the older pvi/npvi report used
an embedded Neovim UI, synthetic Lua files and different revisions. This study
uses PTYs and Python fixtures. It does not isolate why any individual plugin or
feature is expensive, or prove that an old bottleneck has been eliminated.

For a weak server, weigh resource overhead and the measured workflows against
needed features. Vimrc has no LSP; the LSP-disabled baseline does not establish
feature equivalence. Real language servers, NFS, SSH, long sessions and physical
terminal rendering need separate target-server measurements.

[Ctags navigation comparison](flash-vimrc-ctags.md) · [Raw data](flash-pvi-vimrc-results.json)
