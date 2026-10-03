# Ctags: FLASH vs vimrc

[English](flash-vimrc-ctags.md) | [한국어](flash-vimrc-ctags.ko.md)

| Metric                            |               FLASH |               vimrc |
| --------------------------------- | ------------------: | ------------------: |
| First gd, including indexing (ms) | 60.76 (54.87–65.05) | 74.43 (62.81–81.75) |
| Ready-index gd (ms)               |    1.71 (1.67–1.76) |    2.54 (2.52–2.60) |
| Peak RSS including indexing (MiB) | 21.56 (21.42–21.78) | 50.03 (49.97–50.06) |

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
All 21 jumps per process must reach the expected declaration. pvi is not included
in this ctags study: its LSP-disabled gd path is not made equivalent artificially.

[Raw data / 원본 데이터](flash-vimrc-ctags-results.json)
