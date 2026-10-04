# Package-based Neovim configuration structure

[English](package-based-neovim.md) | [한국어](package-based-neovim.ko.md)

`nvim-pack/.config/nvim-pack/init.lua` loads the feature modules directly from
`nvim-pack/.config/nvim-pack/lua/`. Snacks is configured before modules register its toggles.
It resolves its own file location, including symlinks, so `nvim -u /path/to/init.lua`
also works when the adjacent `lua/` directory is present.

***FLASH***'s `nvim/.config/nvim/init.lua` stays independent: it loads feature modules from its own
`lua/` directory and does not import any Package-based Neovim modules. Copy its whole profile directory
when moving it to a server. `vi` always starts ***FLASH***; `pvi` selects `NVIM_APPNAME=nvim-pack`. Package-based Neovim plugins and Mason tools are separate
from these configuration files and must also be available on a network-isolated server.

| Module              | Responsibility                                                    |
| ------------------- | ----------------------------------------------------------------- |
| `options.lua`       | Disable defaults, editor options, leader                          |
| `buffer_policy.lua` | Shared buffer eligibility, guarded actions and restriction events |
| `keymaps.lua`       | Editing, window movement/resizing, cursor word highlight          |
| `bigfile.lua`       | Snacks bigfile configuration and supplemental growth checks       |
| `plugins.lua`       | `vim.pack` package registration                                   |
| `context.lua`       | Native sticky context and its update lifecycle                    |
| `ui.lua`            | Snacks setup: dashboard, indent, picker styling, terminal layout  |
| `git.lua`           | Gitsigns, hunk operations, inline blame                           |
| `session.lua`       | Session persistence                                               |
| `clipboard.lua`     | SSH clipboard copying                                             |
| `whichkey.lua`      | Keybinding help                                                   |
| `pickers.lua`       | Search picker mappings                                            |
| `breadcrumbs.lua`   | Native statusline context, scope navigation and toggle             |
| `breadcrumb_symbols.lua` | Cached LSP symbol hierarchy and request lifecycle             |
| `outline.lua`       | Aerial outline and cursor tracking                                |
| `terminal.lua`      | Bottom terminal and lazygit toggles                               |
| `format.lua`        | Conform formatter registration and formatting                     |
| `completion.lua`    | Native completion and snippets                                    |
| `project.lua`       | Shared project roots, Python library boundaries and root cache    |
| `explorer.lua`      | Oil file explorer, toggle and working-directory updates           |
| `lsp.lua`           | Native LSP, Snacks capability-aware keys, servers, Python, Mason  |
| `buffers.lua`       | Tabline, buffer selection and deletion                            |
| `statusline.lua`    | Statusline rendering and invalidation                             |
| `theme.lua`         | Final editor commands and colorscheme                             |

`ui.lua` passes the configuration from `bigfile.lua` to Snacks. `explorer.lua`
configures Oil and routes its terminal shortcut to the toggle in `terminal.lua`.
Snacks also manages capability-aware LSP keymaps, feature toggle bindings, and
filtered bulk buffer deletion. Sticky context, breadcrumbs, and statusline
rendering keep their existing implementations and default states.
Modules that use Snacks import the installed
`snacks` plugin directly. Configuration module names intentionally differ from
plugin entry points such as `snacks`.

Automatic editing and code-analysis features use `buffer_policy.allows(buf)`;
normal loaded buffers are eligible unless marked as large files. Manual source
operations that should remain available on large files can use `is_source(buf)`,
which also recognizes unloaded normal buffers for buffer lists and sessions.
Manual formatting follows the same protection limits as code analysis.
Use `guard(callback)` for code-analysis keymaps. Do not duplicate `large_file`
checks in feature modules. `bigfile.lua` detects size and edit growth, then calls
`restrict(buf)` once. The policy disables Snacks buffer features and emits
`PackBufferRestricted`; each feature owns its cleanup, including Git/LSP detachment,
pending requests, overlays and outline data. Check eligibility when an action runs
and when an asynchronous result arrives. Global defaults and other buffers stay unchanged.

Statusline breadcrumbs display the cached LSP document-symbol hierarchy without a
Dropbar dependency or indentation-based guesses. `<leader>Td` toggles them; clicking
a symbol jumps to its declaration line. Cursor movement and statusline redraws
never request symbols. File changes and LSP attachment changes refresh the cache;
disabling the feature or restricting/unloading a buffer cancels pending work.
Files without symbol support show only their path. Control-flow blocks appear only
when supplied as symbols by the language server; Dropbar's sibling menus are not
implemented. Python environment selection cancels superseded requests and drops
results after its source is unloaded, renamed or restricted.

New features must use `buffer_policy` for eligibility. Only `bigfile.lua` owns
large-file detection. Connect each plugin's filters, keymaps and cleanup;
a buffer flag alone does not automatically stop an external plugin.

***FLASH*** implements the same contract in its own `buffer_policy.lua`,
without importing Package-based Neovim modules or plugins. Plugin-free Vim keeps the equivalent `IsSource`,
`BufferAllows`, and `RestrictBuffer` helpers inside `.vimrc`. Their
`NopackBufferRestricted` event cancels affected automatic work and clears active
UI. All three profiles protect files exceeding 2 MiB, 50,000 lines, or a single
10,000-byte line. Detection on open and changed-range checks on edits share the
same limits; features may retain stricter workload budgets, such as native Git
sign diff limits. Protection lasts until the buffer is discarded. Buffer lists,
project browsing, and sessions still recognize protected or unloaded source buffers.

When investigating cursor lag, start with the events and callbacks in the relevant
feature module. File splitting does not itself change refresh frequency, introduce
lazy loading, or improve performance. Avoid re-sourcing individual modules during
a running session: their setup code registers mappings and events. Restart Neovim
after changes.

## File explorer

[Oil](https://github.com/stevearc/oil.nvim) replaces Snacks Explorer. `<leader>e`
opens a 40-column directory listing on the left, keeping the editing windows intact;
pressing it again closes only the sidebar. Files open in the editing window while
directories navigate within the sidebar. It uses the same project and Python-library
root selection as ***FLASH***. Directory buffers opened with `:e directory/` also
use Oil. Oil shows one directory at a time, rather than an expandable tree.

Edit file names directly, use `yy` / `p` to duplicate entries or `dd` to delete
them, then `:w` to review and apply the filesystem changes. A new entry ending in
`/` creates a directory. Icons and line numbers are disabled; hidden and
Git-ignored files are visible by default. Oil does not provide the previous
Snacks Explorer Git-status badges. Filesystem watching is disabled, and Oil
buffers/windows are excluded from automatic session saves.

| Key | Action |
| --- | --- |
| `<leader>e` | Open/close Oil |
| `Enter` | Open file in editor / enter directory in sidebar |
| `Ctrl-c` | Close explorer |
| `-` / `_` | Parent directory / editor working directory |
| `Ctrl-p` | Preview entry |
| `gv` / `gh` / `gt` | Open in vertical split / horizontal split / new tab |
| `gR` | Refresh directory listing |
| `g.` | Toggle hidden files |
| `g?` | Show Oil keybinding help |
| `Ctrl-h/j/k/l` | Keep the profile's window navigation |
| `Ctrl-s` | Save directory edits |
| `Ctrl-t` | Toggle the reusable bottom terminal |

## Live sharing

Package-based Neovim installs [peerpad.nvim](https://github.com/Sunwook-Hwang/peerpad.nvim)
through `vim.pack`; `init.lua` calls its setup directly. It interoperates with ***FLASH***'s native live sharing.
`<leader>Ps` starts sharing, `<leader>Pj` joins, `<leader>Pq` disconnects, and
`<leader>Pi` shows session information. The commands are `:Peerpad`,
`:PeerpadJoin`, `:PeerpadStop`, and `:PeerpadStatus`.
Transport loads only when needed; discovery checks once per source-file read.
For disconnected servers, copy this package along with the other Package-based Neovim plugins.

Participants still need a TCP connection even when NFS exposes the same file.
Only the host saves the shared source file.

## Scope and profiling

Snacks Scope uses indentation without Treesitter. `[i` / `]i` jump to scope
edges; `ii` / `ai` select the inner / full scope in visual or operator-pending
mode (for example, `vii` or `dai`). Scope highlighting remains disabled.

The Lua profiler starts disabled. `<leader>Dp` starts/stops recording and opens
results when stopped; `<leader>DP` reopens results; `<leader>Dh` toggles profiling
highlights. Recording adds overhead and captures only supported Lua calls,
including Lua autocmd callbacks registered while recording.
