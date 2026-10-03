# Ctags: ***FLASH*** vs Plugin-free Vim

[English](flash-plugin-free-vim-ctags.md) | [한국어](flash-plugin-free-vim-ctags.ko.md)

Plugin-free Vim does not support LSP, so ***FLASH***'s LSP was disabled and both used the same
project and ctags tool. **Values are seven-process medians (minimum–maximum).**
This matches the navigation task, not every editor capability. Measurements used
a Mac mini M4, Neovim 0.12.5 and Vim 9.2 on 2026-10-03.

**🏆** marks the lowest median in each row, including ties. Percentages are relative to Plugin-free Vim: `(result / baseline − 1) × 100`; negative values mean less time or memory.

| Metric                            |                              ***FLASH*** |            Plugin-free Vim |
| --------------------------------- | ---------------------------------: | -------------------------: |
| First gd, including indexing (ms) | **🏆 60.76 (54.87–65.05); -18.4%** | 74.43 (62.81–81.75); +0.0% |
| Ready-index gd (ms)               |    **🏆 1.71 (1.67–1.76); -32.6%** |    2.54 (2.52–2.60); +0.0% |
| Peak RSS including indexing (MiB) | **🏆 21.56 (21.42–21.78); -56.9%** | 50.03 (49.97–50.06); +0.0% |

Winner markers apply **only to the measured ctags tasks**, not the entire editor or LSP workflows. ***FLASH*** took 18.4% less time on the first lookup and 32.6% less on indexed lookups; the latter absolute difference is only 0.83 ms.

Both editors use their actual mapped `gd` with LSP disabled. The generated Git
project contains 100 Python modules, 1,000 unique functions and a 2,000-line main.py.
The first lookup must reach module_099.py's function_099_009 declaration; 20 repeated
lookups reuse the managed index. Returns to main.py are outside the warm timing.
The per-process warm median is summarized across seven processes, so each process
has equal weight. Execution order alternates for 14 measured launches.

Cold gd includes building the index, async callback delivery, opening the destination
and redraw. Warm gd includes lookup and target redraw. It does not measure LSP,
unsaved-code accuracy, ambiguous results or large network filesystems. The same
PTY and isolation conditions as the three-editor baseline apply; peak RSS also
includes the subsequent common editing workload. Child ctags memory is excluded.
All 21 jumps per process must reach the expected declaration. Package-based Neovim is not included
in this ctags study: its LSP-disabled gd path is not made equivalent artificially.

[Raw data / 원본 데이터](flash-plugin-free-vim-ctags-results.json)
