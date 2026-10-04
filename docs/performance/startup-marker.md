# Startup measurement — three configurations

[English](startup-marker.md) | [한국어](startup-marker.ko.md) · [Raw data](startup-marker-results.json)

Measured on 2026-10-04 at `a19d45a`: Mac mini M4, Neovim 0.12.5, Vim 9.2, LSP disabled. Seven runs per configuration and file, 63 launches total. Values are medians; percentages compare elapsed time.

**This experiment used a PTY that did not answer terminal queries. For the comparison with terminal replies, see [the measurement with terminal replies](startup-cause.md).**

| File | ***FLASH*** (ms) | Package-based Neovim (ms) | Plugin-free Vim (ms) | ***FLASH*** vs package | ***FLASH*** vs Vim |
| --- | ---: | ---: | ---: | ---: | ---: |
| source_2k | 233.28 | 274.71 | 76.52 | -15.1% | +204.9% |
| tracked_git | 195.44 | 245.57 | 74.60 | -20.4% | +162.0% |
| large_60k | 234.57 | 275.36 | 71.60 | -14.8% | +227.6% |

Timing runs from process launch to observation of the initial redraw readiness signal. These values include terminal-query waiting; they do not directly measure visible screen completion or editing responsiveness.
