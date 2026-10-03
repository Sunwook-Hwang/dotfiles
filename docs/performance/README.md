# Editor performance comparisons

Experiments are kept on the `performance-comparison` branch, separate from the
normal configuration branch. No editor configuration is changed by the benchmarks.

## Current configuration

- [FLASH vs pvi vs vimrc](flash-pvi-vimrc.md) / [한국어](flash-pvi-vimrc.ko.md)
- [Raw results](flash-pvi-vimrc-results.json)
- [Ctags: FLASH vs vimrc](flash-vimrc-ctags.md) / [한국어](flash-vimrc-ctags.ko.md)
- [Ctags raw results](flash-vimrc-ctags-results.json)
- [Excluded initial setup experiment](unlocked-startup-exploratory-results.json)
  (individual plugin symlinks triggered installation repair; not used for rankings)

The current comparison uses configuration revision `584ff5a` and records installed
package revisions. FLASH is the default `vi` profile under `nvim/`; the older
reports call that profile `npvi` and use the former directory layout.

## Historical reports

Recovered from the private repository's `readme-revision` branch, commit
`e6e9fce300ec3a998730ddb8e9ae735fc20f07f4`. Reports and raw datasets are preserved
unchanged under `historical/`, without merging private configuration or Git history:

- [npvi vs pvi](historical/no-pack-speedmode.md) / [한국어](historical/no-pack-speedmode.ko.md)
- [Ctags: Vim vs npvi](historical/ctags-vim-vs-npvi.md) / [한국어](historical/ctags-vim-vs-npvi.ko.md)
- [npvi + Neovide vs VS Code](historical/npvi-vs-vscode.md) / [한국어](historical/npvi-vs-vscode.ko.md)

Compare values within a study. Fixtures, configurations, editor builds, timing
boundaries and UI automation differ between studies. Historical values are not
measurements of the current configuration, and none establish performance on an
older Linux server, NFS filesystem or SSH terminal.
