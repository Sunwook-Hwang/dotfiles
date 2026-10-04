# Startup measurement

[English](startup-cause.md) | [한국어](startup-cause.ko.md) · [Raw data](startup-cause-results.json)

2026-10-04, commit `a9ec0d0`. Mac mini M4, Neovim 0.12.5, Vim 9.2; the same 2,000-line Python file, LSP disabled, terminal background/status queries answered. Seven runs per configuration, 21 launches total; values are medians.

| Configuration | Startup (ms) | FLASH vs baseline |
| --- | ---: | ---: |
| ***FLASH*** | **52.69** | — |
| Package-based Neovim | 153.43 | -65.7% |
| Plugin-free Vim | 78.37 | -32.8% |

***FLASH*** took **65.7% less time** than Package-based Neovim and **32.8% less time** than Plugin-free Vim.

Timing runs from process launch to observation of the initial redraw readiness signal. This measures startup in this test environment, not overall editing speed or actual screen presentation.
