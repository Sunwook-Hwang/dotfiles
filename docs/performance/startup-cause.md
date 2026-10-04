# Startup measurement — ***FLASH*** vs Plugin-free Vim

[English](startup-cause.md) | [한국어](startup-cause.ko.md) · [Raw data](startup-cause-results.json)

Measured on 2026-10-04: Mac mini M4, Neovim 0.12.5, Vim 9.2, a 2,000-line Python file, LSP disabled. Terminal background/status queries received replies. Seven runs per configuration; values are medians.

| Configuration | Startup (ms) |
| --- | ---: |
| ***FLASH*** | **60.94** |
| Plugin-free Vim | 78.43 |

***FLASH*** took **22.3% less time** in this comparison.

Timing runs from process launch to observation of the initial redraw readiness signal. It does not directly measure visible screen completion or editing responsiveness; results apply to this test environment.
