# Startup timing remeasurement — ***FLASH***, Package-based Neovim and Plugin-free Vim

[English](startup-marker.md) | [한국어](startup-marker.ko.md) · [Raw data](startup-marker-results.json)

Measured **startup only** on 2026-10-04 at main commit `a19d45a`, without changing configurations.
Seven launches per profile and fixture, **63 launches** total. Values are medians (minimum–maximum).

The follow-up [cause analysis and fix](startup-cause.md) identified Neovim background-query
waiting in the no-response PTY and Python-host discovery costs. Values below are preserved
observations of those conditions, not intrinsic startup rankings in a responding terminal.

## Process launch to initial redraw readiness signal

This is a meaningful **startup indicator for the defined test environment**. Percentage
comparisons within that boundary are valid; it does not directly measure terminal screen
presentation or response to the first input. Percentages use `(FLASH / baseline − 1) × 100`;
negative values mean less elapsed time, not higher overall editing speed.

| Fixture | ***FLASH*** (ms) | Package-based Neovim (ms) | Plugin-free Vim (ms) | ***FLASH*** vs package | ***FLASH*** vs Vim |
| --- | ---: | ---: | ---: | ---: | ---: |
| source_2k | 233.28 (208.69–251.16) | 274.71 (262.27–289.04) | 76.52 (76.09–87.54) | -15.1% | +204.9% |
| tracked_git | 195.44 (189.13–204.63) | 245.57 (227.63–252.85) | 74.60 (72.08–78.48) | -20.4% | +162.0% |
| large_60k | 234.57 (222.69–244.95) | 275.36 (265.99–278.36) | 71.60 (59.42–73.76) | -14.8% | +227.6% |

## Internal time from configuration entry to first redraw

The editor's `reltime()` measures from configuration entry to immediately after `redraw!`.
It excludes process creation, initialization before configuration entry, and readiness
signal transmission/observation. This is a different boundary from the table above;
the difference cannot be attributed to a single unmeasured cause.

| Fixture | ***FLASH*** (ms) | Package-based Neovim (ms) | Plugin-free Vim (ms) |
| --- | ---: | ---: | ---: |
| source_2k | 85.92 (74.07–93.99) | 126.10 (119.97–138.75) | 39.60 (37.87–43.84) |
| tracked_git | 46.93 (45.40–50.17) | 94.59 (79.31–101.72) | 37.06 (34.44–41.37) |
| large_60k | 87.18 (75.29–88.26) | 124.68 (122.34–126.19) | 31.87 (27.53–34.57) |

## Method and limits

- Mac mini M4 (Mac16,10), 10 CPU cores, 16 GiB RAM, macOS 27.0.1. Neovim 0.12.5 and Vim 9.2.
- Same 120×40 PTY, UTF-8 and `TERM=xterm-256color`. Same generated 2,000/60,000-line Python fixtures and current tracked `lua/git.lua`; hashes are in raw data.
- Sequential runs with rotating profile order. Filesystem caches were not flushed; these are not exclusively first cold starts.
- Isolated configuration/data/cache/session/undo paths. Installed plugins were APFS-cloned and the lockfile copied. No plugin installation or update occurred; cloned package Git revisions were unchanged afterward.
- Actual default themes retained: FLASH `ayu`, Package-based Neovim `catppuccin`, Plugin-free Vim `retrobox`.
- LSP startup disabled for both Neovim profiles to retain the prior comparison conditions; Vim has no LSP. This is not LSP-enabled feature parity. Each profile's protective policy activates on the large file.
- The parent starts its clock immediately before `Popen`. A zero-delay timer after `VimEnter` calls `redraw!`, records state and emits a unique PTY string. The parent records time when `select`/`read` observes that string.
- The former 5 ms marker-file polling was removed. Signal output/transmission/observation, state recording and OS scheduling still contribute to end-to-end time; no fixed delay bound is claimed.
- PTY output is drained but no real terminal emulator responds to terminal queries. Effects of that environment may be included and were not isolated. Neither screen presentation nor input response was directly observed.
- All 63 launches exited normally with empty `v:errmsg`, zero LSP clients, one source window and expected large-file policy. Failed preliminary signal-transport attempts were excluded.
- Cursor movement, editing and memory were not remeasured; previous report values remain unchanged. Results on this Mac do not establish startup times on constrained servers, SSH or NFS.
