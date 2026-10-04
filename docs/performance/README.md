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
14 ctags runs and 14 matched ty LSP runs. These are separate protocols. The startup comparison uses 21 launches at `a9ec0d0` with terminal replies.

## Current configuration

- [Startup measurement: all three configurations](startup-cause.md) / [한국어](startup-cause.ko.md) ([raw data](startup-cause-results.json))

- [Matched ty LSP: ***FLASH*** vs Package-based Neovim](flash-package-based-neovim-lsp.md) / [한국어](flash-package-based-neovim-lsp.ko.md) ([raw data](flash-package-based-neovim-lsp-results.json))

- [Ctags: ***FLASH*** vs Plugin-free Vim](flash-plugin-free-vim-ctags.md) / [한국어](flash-plugin-free-vim-ctags.ko.md) ([raw data](flash-plugin-free-vim-ctags-results.json))
- [Performance by use case](editor-baseline.md) / [한국어](editor-baseline.ko.md) ([raw data](editor-baseline-results.json))
- [Excluded initial setup experiment](unlocked-startup-exploratory-results.json)
  (individual plugin symlinks triggered installation repair; not used for rankings)

The no-LSP and ctags comparisons use configuration revision `584ff5a`; the added
LSP study uses `aa2cf6b` (editor configuration unchanged). Installed package
revisions are recorded in each applicable dataset. ***FLASH*** is the default Neovim
configuration under `nvim/`, launched with the `vi` command; the older
reports use the former directory layout. Profile labels and report filenames
use the agreed configuration names here.
