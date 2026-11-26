# rvim Steel Configuration

Steel (`.scm`) port of the FLASH Neovim configuration (`nvim/.config/nvim/`), structured for `~/.config/rvim` via GNU Stow (`stow rvim`).

## Layout

```text
rvim/.config/rvim/
├── init.scm              # Entry point (ports init.lua)
├── scm/                  # Steel modules (1:1 port of lua/*.lua)
├── colors/               # 42 colorscheme loaders (*.scm)
└── themes/
    ├── data/             # 51 theme snapshots converted from Lua tables to JSON
    ├── licenses/         # Upstream theme licenses
    └── README.md         # Upstream theme attributions
```

## Module Correspondence (P0 + P1 + Themes)

Each `.scm` file begins with a header comment noting the exact Lua source and equivalence details.

| Priority | Lua Source (`nvim/.config/nvim/lua/`) | Steel Port (`rvim/.config/rvim/scm/`) | Scope |
| --- | --- | --- | --- |
| Entry | `init.lua` | `../init.scm` | Startup sequencing, `theme`, `options`, `keymaps`, core modules |
| P0 | `state.lua` | `state.scm` | Cross-module mutable state (`state-get`/`state-set!`/`state-call`) |
| P0 | `buffer_policy.lua` | `buffer_policy.scm` | Editable/source/editor buffer predicates and size limits |
| P0 | `syntax.lua` | `syntax.scm` | Treesitter language mapping and highlight activation |
| P0 | `indent.lua` | `indent.scm` | Tabstop/shiftwidth inference and filetype indentation |
| P0 | `diagnostics.lua` | `diagnostics.scm` | Diagnostic virtual text, signs, float, and keymaps |
| P0 | `navigation.lua` | `navigation.scm` | Window/buffer focus helpers, jump motions, quickfix navigation |
| P0 | `theme_loader.lua` | `theme_loader.scm` | JSON theme snapshot loader (`themes/data/<name>.json`) |
| P0 | `theme.lua` | `theme.scm` | Theme persistence, `<leader>C` picker, light/dark toggle |
| P0 | `bigfile.lua` | `bigfile.scm` | Large-file restriction (`NopackBufferRestricted`) |
| P0 | `options.lua` | `options.scm` | Editor options, OSC52 clipboard, yank highlight |
| P0 | `keymaps.lua` | `keymaps.scm` | Core leader/motion/window keymaps |
| P1 | `breadcrumbs.lua` | `breadcrumbs.scm` | Statusline symbol hierarchy + `v:steel.NopackContextJump` |
| P1 | `breadcrumb_symbols.lua` | `breadcrumb_symbols.scm` | Cached LSP documentSymbol hierarchy |
| P1 | `terminal.lua` | `terminal.scm` | Toggleable bottom/float terminal |
| P1 | `project.scm` (`project.lua`) | `project.scm` | Project root detection and persistence |
| P1 | `whichkey.lua` | `whichkey.scm` | Prefix keymap popup helper |
| P1 | `session.lua` | `session.scm` | Per-project session save/restore/picker |
| P1 | `statusline.lua` | `statusline.scm` | WCAG mode branch highlight, diagnostics/LSP cache, `v:steel.NopackStatusline` |
| P1 | `buffers.lua` | `buffers.scm` | Native tabline, split-preserving buffer close, Zen cycle overlay |
| P1 | `editing.lua` | `editing.scm` | IM switch, `<leader>u` undo diff picker, cursor word, Zen mode, smooth scroll |
| P1 | `dashboard.lua` | `dashboard.scm` | Fullscreen floating dashboard (`c` opens `init.scm`) |
| Themes | `themes/data/*.lua` (51) | `../themes/data/*.json` (51) | Lossless canonical JSON theme snapshots |
| Themes | `colors/*.lua` (42) | `../colors/*.scm` (42) | Thin colorscheme loaders (`ayu.scm` preserves `g:ayucolor`) |

Planned follow-up PRs:
- **P2**: `analysis_backend`, `completion`, `formatting`, `git`, `pickers`, `search`, `treesitter`, `explorer`
- **P3**: `lsp`, `lsp_servers`, `dap`, `testing`, `markdown`, `remote`

## Steel Facade Modules (`rvim/*`)

Modules import the planned `rvim/*` Steel facade surface (updated if facade signatures change):
- `rvim/api`, `rvim/opt`, `rvim/keymap`, `rvim/cmd`, `rvim/fn`, `rvim/notify`, `rvim/schedule`
- `rvim/fs`, `rvim/uv`, `rvim/ui`, `rvim/json`, `rvim/diff`, `rvim/system`
- `rvim/lsp`, `rvim/diagnostic`, `rvim/treesitter`, `rvim/hl`, `rvim/clipboard`

Statusline/tabline/breadcrumb callbacks use `v:steel.<Name>` and register handlers in `scm/state.scm`.

## Verification

Run the parity and syntax verifier from the repository root:

```sh
python3 tools/verify_rvim_steel.py
```
