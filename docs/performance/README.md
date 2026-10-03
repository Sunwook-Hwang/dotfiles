# Editor performance comparisons

Reports are available here on the main branch; experiment development used the
`performance-comparison` branch. Benchmarks do not change editor configuration.

## Configuration names

- ***FLASH***: Package-free Native Neovim (***FLASH***), launched with `vi`.
- **Package-based Neovim**: the plugin-backed configuration launched with `pvi`.
- **Plugin-free Vim**: the Vim configuration loaded from `~/.vimrc`, launched with `vim`.

The names identify configurations, not new editor binaries. The main editor-comparison JSON files use the
profile identifiers `flash`, `package_based_neovim` and `plugin_free_vim`;
version fields still name the actual Neovim and Vim executables.

## Compare by use case

There is no overall winner across these different feature sets. The existing
measurements are organized as:

1. ***FLASH*** vs Package-based Neovim: matched ty LSP tasks now measured, with identical server/version,
   Python environment, project, capabilities and settings. A separate no-LSP
   editing baseline is retained; full feature parity remains unmeasured.
2. ***FLASH*** vs Plugin-free Vim: Plugin-free Vim has no LSP, so ***FLASH***'s LSP was disabled to match
   ctags definition-navigation tasks in the same project with the same tool.
3. Protected large files: separate policy-dependent results, not full-feature
   performance. Plugin-free Vim's common editing values are retained as reference data.

Percentages use the unrounded raw medians and describe individual task costs,
not overall editor speed. The 91 launches comprise 63 common editing runs,
14 ctags runs and 14 matched ty LSP runs. These are separate protocols.

## Current configuration

- [Matched ty LSP: ***FLASH*** vs Package-based Neovim](flash-package-based-neovim-lsp.md) / [한국어](flash-package-based-neovim-lsp.ko.md)
- [LSP raw results](flash-package-based-neovim-lsp-results.json)

- [Performance by use case](editor-baseline.md) / [한국어](editor-baseline.ko.md)
- [Raw results](editor-baseline-results.json)
- [Ctags: ***FLASH*** vs Plugin-free Vim](flash-plugin-free-vim-ctags.md) / [한국어](flash-plugin-free-vim-ctags.ko.md)
- [Ctags raw results](flash-plugin-free-vim-ctags-results.json)
- [Excluded initial setup experiment](unlocked-startup-exploratory-results.json)
  (individual plugin symlinks triggered installation repair; not used for rankings)

The no-LSP and ctags comparisons use configuration revision `584ff5a`; the added
LSP study uses `aa2cf6b` (editor configuration unchanged). Installed package
revisions are recorded in each applicable dataset. ***FLASH*** is the default Neovim
configuration under `nvim/`, launched with the `vi` command; the older
reports use the former directory layout. Profile labels and report filenames
use the agreed configuration names here.

## Historical reports

Recovered from the private repository's `readme-revision` branch, commit
`e6e9fce300ec3a998730ddb8e9ae735fc20f07f4`. Reports and datasets are retained under `historical/`, without merging private
configuration or Git history. Profile labels, JSON profile keys, filenames and
links use ***FLASH***, Package-based Neovim and Plugin-free Vim; measured values remain unchanged:

- [***FLASH*** vs Package-based Neovim](historical/flash-package-baseline.md) / [한국어](historical/flash-package-baseline.ko.md)
- [Ctags: Plugin-free Vim vs ***FLASH***](historical/ctags-plugin-free-vim-vs-flash.md) / [한국어](historical/ctags-plugin-free-vim-vs-flash.ko.md)
- [***FLASH*** + Neovide vs VS Code](historical/flash-vs-vscode.md) / [한국어](historical/flash-vs-vscode.ko.md)

Compare values within a study. Fixtures, configurations, editor builds, timing
boundaries and UI automation differ between studies. Historical values are not
measurements of the current configuration, and none establish performance on an
older Linux server, NFS filesystem or SSH terminal.
