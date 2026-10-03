# Editor performance comparisons

Experiments are kept on the `performance-comparison` branch, separate from the
normal configuration branch. No editor configuration is changed by the benchmarks.

## Compare by use case

There is no overall winner across these different feature sets. The existing
measurements are organized as:

1. FLASH vs pvi: matched ty LSP tasks now measured, with identical server/version,
   Python environment, project, capabilities and settings. A separate no-LSP
   editing baseline is retained; full feature parity remains unmeasured.
2. FLASH vs vimrc: vimrc has no LSP, so FLASH's LSP was disabled to match
   ctags definition-navigation tasks in the same project with the same tool.
3. Protected large files: separate policy-dependent results, not full-feature
   performance. Vim's common editing values are retained as reference data.

Percentages use the unrounded raw medians and describe individual task costs,
not overall editor speed. The 91 launches comprise 63 common editing runs,
14 ctags runs and 14 matched ty LSP runs. These are separate protocols.

## Current configuration

- [Matched ty LSP: FLASH vs pvi](flash-pvi-lsp.md) / [한국어](flash-pvi-lsp.ko.md)
- [LSP raw results](flash-pvi-lsp-results.json)

- [Performance by use case](flash-pvi-vimrc.md) / [한국어](flash-pvi-vimrc.ko.md)
- [Raw results](flash-pvi-vimrc-results.json)
- [Ctags: FLASH vs vimrc](flash-vimrc-ctags.md) / [한국어](flash-vimrc-ctags.ko.md)
- [Ctags raw results](flash-vimrc-ctags-results.json)
- [Excluded initial setup experiment](unlocked-startup-exploratory-results.json)
  (individual plugin symlinks triggered installation repair; not used for rankings)

The no-LSP and ctags comparisons use configuration revision `584ff5a`; the added
LSP study uses `aa2cf6b` (editor configuration unchanged). Installed package
revisions are recorded in each applicable dataset. FLASH is the default Neovim
configuration under `nvim/`, launched with the `vi` command; the older
reports use the former directory layout. Profile labels and report filenames
are normalized to FLASH here.

## Historical reports

Recovered from the private repository's `readme-revision` branch, commit
`e6e9fce300ec3a998730ddb8e9ae735fc20f07f4`. Reports and datasets are retained under `historical/`, without merging private
configuration or Git history. Profile labels, JSON profile keys, filenames and
links are updated to FLASH; measured values remain unchanged:

- [FLASH vs pvi](historical/no-pack-speedmode.md) / [한국어](historical/no-pack-speedmode.ko.md)
- [Ctags: Vim vs FLASH](historical/ctags-vim-vs-flash.md) / [한국어](historical/ctags-vim-vs-flash.ko.md)
- [FLASH + Neovide vs VS Code](historical/flash-vs-vscode.md) / [한국어](historical/flash-vs-vscode.ko.md)

Compare values within a study. Fixtures, configurations, editor builds, timing
boundaries and UI automation differ between studies. Historical values are not
measurements of the current configuration, and none establish performance on an
older Linux server, NFS filesystem or SSH terminal.
