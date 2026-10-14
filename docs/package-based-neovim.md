# Package-based Neovim configuration structure

[English](package-based-neovim.md) | [한국어](package-based-neovim.ko.md)

`nvim-pack/.config/nvim-pack/init.lua` loads the feature modules directly from
`nvim-pack/.config/nvim-pack/lua/`. Large-file protection is registered before plugin setup.
It resolves its own file location, including symlinks, so `nvim -u /path/to/init.lua`
also works when the adjacent `lua/` directory is present.

***FLASH***'s `nvim/.config/nvim/init.lua` stays independent: it loads feature modules from its own
`lua/` directory and does not import any Package-based Neovim modules. Copy its whole profile directory
when moving it to a server. `vi` always starts ***FLASH***; `pvi` selects `NVIM_APPNAME=nvim-pack`. Package-based Neovim plugins and Mason tools are separate
from these configuration files and must also be available on a network-isolated server.

| Module              | Responsibility                                                    |
| ------------------------ | ----------------------------------------------------------------- |
| `options.lua`       | Disable defaults, editor options, leader                          |
| `buffer_policy.lua` | Shared buffer eligibility, guarded actions and restriction events |
| `keymaps.lua`       | Editing, window movement/resizing, cursor word highlight          |
| `window.lua`        | Reversible editor zoom and split-layout tracking                  |
| `files.lua`         | Event-driven external file refresh                               |
| `bigfile.lua`            | Native open, reload and changed-range protection                  |
| `plugins.lua`       | `vim.pack` package registration                                   |
| `context.lua`       | Native sticky context and its update lifecycle                    |
| `ui.lua`                 | Notifications, input, indent guides, scope, dim and profiling     |
| `git.lua`           | Gitsigns, hunk operations, inline blame                           |
| `session.lua`       | Session persistence                                               |
| `clipboard.lua`     | SSH clipboard copying                                             |
| `whichkey.lua`      | Keybinding help                                                   |
| `pickers.lua`            | Telescope setup, native fuzzy sorting and picker mappings         |
| `breadcrumbs.lua`   | Native statusline context, scope navigation and toggle             |
| `breadcrumb_symbols.lua` | Cached LSP symbol hierarchy and request lifecycle             |
| `outline.lua`       | Aerial outline and cursor tracking                                |
| `terminal.lua`      | Reusable terminal, restart, fullscreen and Git status             |
| `format.lua`        | Conform formatter registration and formatting                     |
| `completion.lua`    | Native completion and snippets                                    |
| `project.lua`       | Shared project roots, Python library boundaries and root cache    |
| `explorer.lua`      | Oil file explorer, toggle and working-directory updates           |
| `lsp.lua`                | Native LSP, capability-aware keys, servers, Python, Mason         |
| `buffers.lua`       | Tabline, buffer selection and deletion                            |
| `statusline.lua`    | Statusline rendering and invalidation                             |
| `theme.lua`         | Final editor commands and colorscheme                             |

`dashboard.lua` configures Alpha. `pickers.lua` loads Telescope on first use,
with Plenary, fzf-native and the UI-select extension. `undo_picker.lua` runs
Telescope Undo on an isolated buffer so browsing history never changes the source
buffer or sends temporary edits to its LSP or Peerpad session.
`native_build.lua` builds fzf-native after installation or source updates.

Oil, Aerial, Gitsigns, Conform, Persistence and Which-key keep their existing roles.
The terminal, statuscolumn, statusline, tabline, sticky context and breadcrumbs use
native Neovim APIs. `mini.bufremove` preserves window layouts during buffer removal.
There is no Snacks or Toggleterm dependency.

Automatic editing and code-analysis features use `buffer_policy.allows(buf)`;
normal loaded buffers are eligible unless marked as large files. Manual source
operations that should remain available on large files can use `is_source(buf)`,
which also recognizes unloaded normal buffers for buffer lists and sessions.
Manual formatting follows the same protection limits as code analysis.
Use `guard(callback)` for code-analysis keymaps. Do not duplicate `large_file`
checks in feature modules. `bigfile.lua` detects size and edit growth, then calls
`restrict(buf)` once. The policy emits
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

## Editing and navigation

These actions match ***FLASH*** using Telescope pickers and a reusable native terminal.

| Key | Action |
| ---------------------------- | ---------------------------------------------------------------------------- |
| `*` / `#` | Set a forward / backward word search without moving; navigate with `n` / `N` |
| `Ctrl-w o` / `Ctrl-w Ctrl-o` | Toggle editor zoom and restore the original split layout |
| `Ctrl-t` | Show/hide the same bottom-terminal shell |
| `<leader>TT` | Stop that shell and start a new one in the editor window's `:pwd` |
| `Ctrl-\` then `\` | Toggle terminal fullscreen from an editor, sidebar or terminal |
| `<leader>gg`                 | Open lazygit, or the Telescope Git-status picker when lazygit is unavailable |
| `<leader>lD` / `<leader>sd` | Current-buffer / all-buffer diagnostics, errors first |
| `<leader>sk` | Search keymaps, with the configured leader displayed as `<leader>` |

Adding an editor split during editor zoom starts a new layout; auxiliary windows do
not discard the saved layout. Terminal fullscreen preserves the shell and returns
to the previous window; it also works when the terminal is hidden or not yet created.
Hold `Ctrl` for both backslashes if preferred. `Ctrl-\ Ctrl-n` still enters terminal
normal mode. Session saves restore temporary editor/terminal zoom and exclude utility buffers;
Neovim 0.13's native session-writing events use the same filter.

Diagnostic lists use bold, colored `E/W/I/H` prefixes. Diagnostics and the LSP restart
key remain accessible when a client is disconnected. Active statuslines are bold;
inactive statuslines remain regular weight.

Neovim 0.13 uses native `autoread` file watching. On 0.12, entering a source buffer
checks that file; returning from a terminal or another application checks loaded files.
No cursor-movement polling is added, and unsaved edits are not overwritten.

## File explorer

[Oil](https://github.com/stevearc/oil.nvim) provides the file explorer. `<leader>e`
opens a 40-column directory listing on the left, keeping the editing windows intact;
pressing it again closes only the sidebar. Files open in the editing window while
directories navigate within the sidebar. It uses the same project and Python-library
root selection as ***FLASH***. Directory buffers opened with `:e directory/` also
use Oil. Oil shows one directory at a time, rather than an expandable tree.

Edit file names directly, use `yy` / `p` to duplicate entries or `dd` to delete
them, then `:w` to review and apply the filesystem changes. A new entry ending in
`/` creates a directory. Icons and line numbers are disabled; hidden and
Git-ignored files are visible by default.
[oil-git.nvim](https://github.com/malewicz1337/oil-git.nvim) adds asynchronous Git
status for files and directories in a fixed-width sign column: `+` added, `M`
modified, `R` renamed, `D` deleted, `C` copied, `U` conflicted, `?` untracked,
`!` ignored. Oil filesystem watching is disabled, and Oil buffers/windows are
excluded from automatic session saves.

Navigation keys match ***FLASH*** where Oil supports the action. `<localleader>`
defaults to `\` unless you set `vim.g.maplocalleader`. Oil does not provide
***FLASH***'s folder expansion/collapse or separate Git-ignore visibility toggle.

| Key | Action |
| ------------------------------------------------------ | --------------------------------------------------- |
| `<leader>e` | Open/close Oil |
| `Enter` | Open file in editor / enter directory in sidebar |
| `Ctrl-c` | Close explorer |
| `-` / `<localleader>w` | Parent directory / editor working directory |
| `<localleader>p` | Toggle entry preview |
| `<localleader>v` / `<localleader>s` / `<localleader>t` | Open in vertical split / horizontal split / new tab |
| `<localleader>d` / `<localleader>D` | Set global / tab working directory |
| `gr` | Refresh directory listing and Git status |
| `g.` | Toggle hidden files |
| `gs` | Choose sort order |
| `gx` | Open in an external application |
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

`mini.indentscope` uses indentation without Treesitter, evaluated only on a scope keypress. `[i` / `]i` jump to scope
edges; `ii` / `ai` select the inner / full scope in visual or operator-pending
mode (for example, `vii` or `dai`). Scope highlighting remains disabled.

The Plenary LuaJIT sampling profiler starts disabled. `<leader>Dp` starts/stops
recording and opens the text report; `<leader>DP` reopens it. Recording adds overhead.
Line-by-line profiling highlights are not provided.

`<leader>Ti` toggles indent-blankline guides. `<leader>TS` toggles mini.animate
scrolling and `<leader>Tm` toggles Twilight dimming; scrolling and dimming start off.
No Treesitter parser is required for these features. Notifications use mini.notify;
input dialogs use NUI, with native input retained for completion/highlight callbacks.

## Search

`<leader>f` finds files; `<leader>st` searches project text; `<leader>t` searches the
word under the cursor. Hidden files are included while Git ignore rules remain active.
`<leader>sp` previews themes and restores the previous theme on cancellation.
`gd` jumps directly for one definition; multiple definitions use Telescope without
sending a second LSP request. Preview highlighting uses Vim syntax, without bat or parsers.

fzf-native is a C fuzzy sorter inside Telescope, not an external terminal UI.
Install `ripgrep` for file/text search. Build the sorter with `:PackBuildFzf` if it
was copied without a compiled library. macOS/Linux need `make` and a C compiler;
Windows uses CMake and a compatible C build toolchain. Normal startup never builds.
If the library cannot load, Telescope uses its Lua sorter and reports the missing build.

## Update from a release

The release asset **pvi.zip** contains this profile, all registered plugins and the
matching `nvim-pack-lock.json`. It can start without downloading plugins. This is
a separate asset from GitHub's automatic **Source code (zip)**.

```sh
curl -fLO https://github.com/Sunwook-Hwang/dotfiles/releases/latest/download/update_pvi.sh
sh ./update_pvi.sh
```

For a disconnected server, download `update_pvi.sh` and `pvi.zip` from the
[latest release](https://github.com/Sunwook-Hwang/dotfiles/releases/latest), transfer
both files, then run from the directory where you want the extracted files:

```sh
sh ./update_pvi.sh /path/to/pvi.zip
env NVIM_APPNAME=nvim-pack nvim
```

The script works from zsh, Bash or C shell when invoked with `sh`; do not source it.
It requires `unzip`, `make` and a C compiler; `curl` is needed only when downloading.
The installer builds fzf-native for the destination machine before replacing the old installation, without network access. Running the profile requires
Neovim 0.12+ and Git. The existing `pvi` alias remains usable.

It backs up and replaces `~/.config/nvim-pack` and
`~/.local/share/nvim-pack/site/pack/core/opt`, respecting `XDG_CONFIG_HOME` and
`XDG_DATA_HOME`. Existing symlinks are backed up as links. FLASH, Mason tools,
sessions and undo history are preserved. Close pvi before installing, then restart.
LSP servers, formatters and other external binaries must be supplied separately
for the target OS and architecture; the Mason plugins themselves are included.

To build the asset from installed plugins, use
`python3 scripts/build_pvi_release.py /path/to/pvi.zip`. The builder requires
Python 3.9+, Neovim, Git and `zip`; it verifies the installed revisions against
the local lockfile and includes upstream source and license files.
