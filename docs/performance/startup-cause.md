# Startup latency causes and fix

[English](startup-cause.md) | [한국어](startup-cause.ko.md) · [Raw data](startup-cause-results.json)

Investigated the 2,000-line Python startup case on 2026-10-04 against main `a19d45a`.
After-fix runs include the uncommitted `options.lua` patch retained in raw data.
The earlier large gap does not establish a fundamental Neovim performance limit.

## Confirmed causes

1. **Unanswered terminal queries in the harness.** Before user configuration, Neovim 0.12.5
   queries OSC11/DSR and runs `vim.wait` with a 100 ms timeout. No-response traces spent about
   114–116 ms in `vim._core.defaults`; representative traces with replies to every background/DSR
   query spent about 1.5–1.6 ms. Lua interpreter initialization itself was about 0.2–0.3 ms in those traces.
2. **Unused Python-host discovery.** The native Python ftplugin calls `has('python3')`, triggering
   synchronous interpreter discovery for the `pynvim` host. Representative pre-fix traces spent
   about 46–49 ms in `provider/python3.vim`. FLASH uses native LSP/buffer completion, so automatic
   discovery is now disabled unless a user explicitly specifies `python3_host_prog`.

Terminal protocols and `ttyfast` were not disabled in configuration. The first cause was
isolated by correcting the harness environment; only the second was changed in FLASH code.

## Results with terminal replies

Median elapsed time from process launch to initial redraw readiness signal observation.
FLASH and Vim were run seven times each in rotating order within each batch.
The Vim configuration was unchanged; its difference between batches is run variation.

| State | FLASH (ms) | Plugin-free Vim (ms) |
| --- | ---: | ---: |
| Before Python-host fix | 102.13 | 71.73 |
| After Python-host fix | 60.94 | 78.43 |

FLASH's before/after median fell **40.3%**. In the after-fix batch it took
**22.3% less time** than the Vim configuration. These are not direct screen-presentation
or input-response measurements, nor guarantees for other languages or servers.

## Minimal runtime control

Both minimal profiles enable filetype plugins, indentation and syntax. Neovim's Python-host
probe is disabled and terminal queries receive replies. Seven runs each. The shared harness
still includes its native Neovim LSP-disable prelude, so this is not exactly `nvim -u NONE`.

| Boundary | Minimal Neovim (ms) | Minimal Vim (ms) |
| --- | ---: | ---: |
| Process launch → readiness signal | 45.59 | 38.31 |
| Configuration entry → first redraw | 13.19 | 15.67 |

About 7 ms remains in the end-to-end measure; Neovim is shorter in the internal boundary.
Build-specific costs, process initialization and measurement variation cannot be treated
as an unavoidable language/architecture limit. Most of the initial 150+ ms gap had separately
identified causes.

## Validation and limits

- Python syntax/indent, real ty attachment, definition navigation and completion passed on Neovim 0.12.5 and the 0.13 development build.
- Python executables, ty/Pyright and formatters remain enabled. Only the separate `:python3`/pynvim host interface defaults off; an explicit host opts in.
- Same Mac mini M4, isolated paths, PTY and generated fixture. 21 minimal exploratory launches, 28 before-fix responding launches, 28 after-fix responding launches and 14 minimal-control launches. Incomplete preliminary terminal-reply attempts and single diagnostic traces are excluded from ranking datasets.
- The responder only supplies OSC11 black background and normal DSR replies. It is not a full terminal emulator and does not reproduce every protocol.
- Timing boundaries and terminal conditions differ from the initial no-response measurement. Actual SSH, NFS and constrained-server startup were not measured.

## Sources

- [Neovim 0.12.5 defaults: background-query wait](https://github.com/neovim/neovim/blob/v0.12.5/runtime/lua/vim/_core/defaults.lua)
- [Neovim 0.12.5 Python ftplugin: provider capability probe](https://github.com/neovim/neovim/blob/v0.12.5/runtime/ftplugin/python.vim)
- [Neovim Python provider](https://github.com/neovim/neovim/blob/v0.12.5/runtime/lua/vim/provider/python.lua)
