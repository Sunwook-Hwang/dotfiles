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

## Module Correspondence (P0 + P1 + P2 + Themes)

Each `.scm` file begins with a header comment noting the exact Lua source and equivalence details.

| Priority | Lua Source (`nvim/.config/nvim/lua/`) | Steel Port (`rvim/.config/rvim/scm/`) | Scope |
| --- | --- | --- | --- |
| Entry | `init.lua` | `../init.scm` | Startup sequencing for P0–P2 modules |
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
| P1 | `project.lua` | `project.scm` | Project root detection and persistence |
| P1 | `whichkey.lua` | `whichkey.scm` | Prefix keymap popup helper |
| P1 | `session.lua` | `session.scm` | Per-project session save/restore/picker |
| P1 | `statusline.lua` | `statusline.scm` | WCAG mode branch highlight, diagnostics/LSP cache, `v:steel.NopackStatusline` |
| P1 | `buffers.lua` | `buffers.scm` | Native tabline, split-preserving buffer close, Zen cycle overlay |
| P1 | `editing.lua` | `editing.scm` | IM switch, `<leader>u` undo diff picker, cursor word, Zen mode, smooth scroll |
| P1 | `dashboard.lua` | `dashboard.scm` | Fullscreen floating dashboard (`c` opens `init.scm`) |
| P2 | `analysis_backend.lua` | `analysis_backend.scm` | Per-buffer LSP vs Ctags backend selection cache |
| P2 | `jobs.lua` | `jobs.scm` | Keyed async command runner, timeout/output caps, `:NopackCancel` |
| P2 | `document_symbols.lua` | `document_symbols.scm` | Shared LSP `documentSymbol` RPC cache and listener fan-out |
| P2 | `format.lua` | `format.scm` | Async external formatters + LSP fallback, `v:steel.NopackFormatStatus` |
| P2 | `fzf_picker.lua` | `fzf_picker.scm` | External `fzf` PTY float with OSC 51 preview |
| P2 | `pickers.lua` | `pickers.scm` | Shared 3-pane fuzzy picker, async file preview, `ui-select`, quickfix |
| P2 | `search.lua` | `search.scm` | Project/config/recent file pickers, metadata pickers, live `rg`/grep |
| P2 | `context.lua` | `context.scm` | Indentation-based sticky scroll overlay (`<leader>Ts`) |
| P2 | `outline.lua` | `outline.scm` | Right sidebar symbol outline (LSP + Ctags, two-way cursor tracking) |
| P2 | `tags.lua` | `tags.scm` | Universal/Exuberant Ctags index builder + `gd` LSP/Ctags dispatcher |
| P2 | `git_actions.lua` | `git_actions.scm` | Hunk stage/reset/undo, inline preview, deleted lines, `ih`, full blame |
| P2 | `git.lua` | `git.scm` | Explorer Git signs, statusline branch, diffs, lazygit, inline blame, gutter signs |
| P2 | `explorer.lua` | `explorer.scm` | Editable directory tree (`flash://`), transactional `:w` staging & rollback |
| Themes | `themes/data/*.lua` (51) | `../themes/data/*.json` (51) | Lossless canonical JSON theme snapshots |
| Themes | `colors/*.lua` (42) | `../colors/*.scm` (42) | Thin colorscheme loaders (`ayu.scm` preserves `g:ayucolor`) |

Planned follow-up PR:
- **P3**: `completion`, `file_watch`, `project_watch`, `lsp/*`, `peerpad/*`

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
