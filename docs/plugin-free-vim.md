# Plugin-free Vim — Vim 9.0+

[한국어](plugin-free-vim.ko.md) · [Configuration](../vim/.vimrc) · [Neovim counterpart](flash.md)

The standalone `.vimrc` uses native Vimscript, **no third-party plugins, no plugin manager, no
Lua, no startup downloads**. An optional separate `~/.vim/lsp.vim` enables vim-lsp. Vim's bundled runtime supplies syntax highlighting,
filetype indentation, completion, diff, terminals, and popup windows. The editable
file tree is implemented in this configuration using native buffers and jobs.

## Start and install

```sh
vim -Nu /path/to/dotfiles/vim/.vimrc
```

The configuration requires Vim **9.0 or newer**, with `+timers`, `+job`,
`+channel`, `+popupwin`, and `+cryptv` (for `sha256()`). Use `vim --version` to
check the build; a Tiny/minimal build is insufficient. `+terminal` enables the
embedded terminal and lazygit popup. Neither Python nor Lua interpreter support
is required.

For the normal repository installation, run `./install_dotfiles.sh`; it links
`vim/.vimrc` to `~/.vimrc`, backing up a conflicting file. `./clean_dotfiles.sh`
removes that link. On a restricted server, copy just `vim/.vimrc` to `~/.vimrc`
and run `vim`. Existing `pvi` / `vi` aliases continue to launch **Neovim**;
this configuration is launched with **`vim`**.

For release updates, [`update_vims.sh`](flash.md#update-from-a-release) backs up
and replaces Vim, FLASH and Package-based Neovim settings together; plugins are separate.

Caches, persistent undo, and sessions are stored under
`~/.vim/nopack`. Set `VIM_NOPACK_DATA` before starting Vim to change this
directory. Third-party directories are excluded from `runtimepath` and
`packpath`, so an existing Vim plugin installation is not loaded.

## Editing and navigation

The leader key defaults to Space; `<leader>` below refers to that key.
`:restart` (or `:Restart`) reloads `~/.vimrc`; it does not restart the Vim process.

| Key                                                             | Action                                                                       |
| --------------------------------------------------------------- | ---------------------------------------------------------------------------- |
| `gcc`                                                           | Toggle the current line's comment; accepts a count                           |
| `gc` + motion                                                   | Toggle comments over a motion, e.g. `gcj` or `gcap`                          |
| Visual `gc`                                                     | Toggle comments on selected lines                                            |
| `.`                                                             | Repeat the comment operation                                                 |
| `Y` / `yy`                                                      | Copy from the cursor to end of line / copy the whole line, matching Neovim   |
| `Q`                                                             | Repeat the last macro recorded with `q`; supports a count                    |
| Linewise Visual `Q` / `@a`                                      | Run the last recorded macro / register `a` on each selected line             |
| Insert `Ctrl-u` / `Ctrl-w`                                      | Delete preceding input / word with a separate undo point                     |
| `&`                                                             | Repeat the last substitution, preserving flags such as `g`                   |
| Normal `*` / `#`                                                | Highlight the cursor word forward / backward without moving; use `n/N` to navigate |
| Visual `*` / `#`                                                | Search the selected text literally, forward / backward, preserving registers |
| `[Space` / `]Space`                                             | Add blank lines above / below; supports counts, undo, and `.`                |
| `[q` / `]q`, `[l` / `]l`, `[a` / `]a`, `[t` / `]t`              | Previous / next quickfix item, location item, argument, or tag match         |
| `[Q` / `]Q`, `[L` / `]L`, `[A` / `]A`, `[T` / `]T`, `[B` / `]B` | First / last item in those lists or the buffer list                          |
| `>>` / `<<`                                                     | Shift the current line right / left, including first-column Python comments  |
| Visual `>` / `<`                                                | Shift selected lines and keep the selection for repeated shifts              |
| `Ctrl-s`                                                        | Save from Normal or Insert mode                                              |
| `jk`                                                            | Leave Insert mode                                                            |
| `Ctrl-h/j/k/l`                                                  | Move between windows                                                         |
| `Ctrl-w o` / `Ctrl-w Ctrl-o`                                    | Toggle editor zoom; adding another editor split keeps the new layout         |
| `Ctrl-Space`                                                    | Request native word/tag completion                                           |
| `Ctrl-n/p`, `Tab`, `Shift-Tab`                                  | Move through completion candidates                                           |
| `Enter`                                                         | Accept a selected completion; otherwise insert a newline                     |

Comments use the current filetype's `commentstring`. Brackets, quotes, and
backticks pair automatically; existing closers are skipped and Backspace removes
empty pairs. Syntax colors and indentation come from Vim's bundled runtime.
The theme is `retrobox` when bundled, otherwise `desert`.
In compatible terminals, the cursor is a block in Normal mode, a vertical bar in
Insert mode, and an underline in Replace mode.

Basic editing defaults also match ***FLASH***: incremental search, one space when `J`
joins sentences, comment-leader removal on joins, retained cursor columns for
`gg`/`G`, decimal handling of zero-prefixed numbers, and filetype-based indentation.
Vim's bundled matchit extends `%`/`g%` to language constructs and HTML tags.
The standalone file does not emulate LSP or Tree-sitter. The optional configuration below adds real LSP support.

## Optional LSP

[`vim/.vim/lsp.vim`](../vim/.vim/lsp.vim) is loaded only when present. It enables
[vim-lsp](https://github.com/prabirshrestha/vim-lsp) from
`~/.vim/pack/vendor/opt/vim-lsp`, with `asyncomplete.vim` and
`asyncomplete-lsp.vim` alongside it for automatic completion. Other installed Vim
plugins remain excluded.
Stow installs the configuration file. For a manual server transfer, copy it to
`~/.vim/lsp.vim` alongside the standalone `~/.vimrc`.

Install the optional LSP and completion plugins on a connected machine:

```sh
git clone https://github.com/prabirshrestha/vim-lsp.git ~/.vim/pack/vendor/opt/vim-lsp
git clone https://github.com/prabirshrestha/asyncomplete.vim.git ~/.vim/pack/vendor/opt/asyncomplete.vim
git clone https://github.com/prabirshrestha/asyncomplete-lsp.vim.git ~/.vim/pack/vendor/opt/asyncomplete-lsp.vim
```

Alternatively, install the release plugin bundle with the shared installer:

```sh
sh ./update_pack.sh vim                         # Download the latest vimpack.zip
sh ./update_pack.sh vim /path/to/vimpack.zip     # Offline ZIP
```

The installer backs up and replaces only these three plugins. Unrelated plugins
and editor settings are preserved; failed replacement restores the previous plugins.
Update the configuration separately with `update_vims.sh`.

On a disconnected server, copy those three plugin directories instead. No plugin
manager, Python host, Lua host or startup download is required. Without the
completion pair, LSP remains available through manual completion (`Ctrl-Space`).
Set `g:vim_lsp_path` before sourcing `.vimrc` for a different plugin location.
Remove `~/.vim/lsp.vim` or the plugin to use only ctags again.

Only installed language servers are registered: executables are resolved from
PATH, then existing Neovim Mason installations. Python prefers ty to pyright;
TypeScript receives the installed `tsserver` path when available. The primary
languages match ***FLASH*** (Python, C/C++/CUDA, Rust, Lua, JavaScript/TypeScript,
Verilog/SystemVerilog, shell, CMake, YAML, TeX, HTML/CSS, Svelte, GraphQL, Prisma,
MLIR, Bzl and Protobuf). Project-specific auxiliary servers are not registered.

A language with a configured server keeps LSP ownership during startup or failure;
ctags is used only when no server is configured for that language. Asyncomplete
provides automatic LSP completion only in eligible editing buffers; native word
and tag completion remains in use without LSP. Diagnostics, semantic colors and
edits use vim-lsp's client.
The existing external formatter remains preferred, with LSP formatting as fallback.
Vim-lsp's background transport and protocol support differ from Neovim's native
client; its size limit controls UI features, not complete per-buffer detachment.

| Key | Action |
| --- | --- |
| `gd`, `gr`, `gD` | Definition, references, declaration; a single result jumps directly |
| `gR`, `gi`, `gt` | Select references, implementations, type definitions in the native picker |
| `K`, `<leader>lr`, `<leader>la` | Hover, rename, code action (also Visual) |
| `<leader>ls` / `:LspRestart`, `<leader>li` | Restart the buffer's configured server, show LSP status |
| `<leader>lv` | Select the project's Python environment (.venv, Conda, PATH or manual path); automatic selection is also available |
| `<leader>ld`, `<leader>lD`, `<leader>sd` | Line, buffer, workspace diagnostics |
| `[d`, `]d`, `<leader>lt` | Previous/next diagnostic, toggle diagnostic display |
| `<leader>o` | Native right-hand live LSP outline with bidirectional following |
| `<leader>lf`, `Ctrl-Space` | Format, request completion |

Diagnostics use bold colored E/W/I/H labels and sort errors first. The active
statusline shows diagnostic counts and the LSP name; inactive windows keep the
existing minimal statusline. No server is restarted after formatting automatically.
Diagnostics tagged `Unnecessary` by the server are dimmed using the theme's Comment color;
ordinary hints are not dimmed.

## ctags instead of LSP

Install **Universal Ctags** on `PATH` (recommended). Exuberant Ctags is also
accepted; macOS's BSD `ctags` is not. Universal is preferred across `PATH`
candidates. An explicit executable can be supplied with `g:nopack_ctags`.

| Key / command             | Action                                                                |
| ------------------------- | --------------------------------------------------------------------- |
| `gd`                      | Build the project index if needed, then jump to the word's definition |
| `g Ctrl-t`                | Return through Vim's tag stack (`Ctrl-t` is the terminal toggle)      |
| `<leader>o`                 | Toggle the right-hand ctags outline                                   |
| Outline `Enter`, `r`, `q` | Jump, refresh from the saved file, close                              |
| `:CtagsUpdate`            | Rebuild the whole current project index                               |
| `:CtagsClearAll`          | Remove managed tag caches                                             |
| `:NopackCancel`           | Cancel background commands and the active picker                      |

The first completion request in a file indexes that saved file. Project
definition lookup builds a full index asynchronously; subsequent saves queue
incremental updates without cancelling an in-flight full build. Old definitions
from changed files are replaced, including removed symbols. Rebuild explicitly
after external deletions/renames. In Git projects the index includes tracked
and untracked files while respecting `.gitignore`. Outside Git, common build,
dependency, and virtual-environment directories are excluded. Available
languages depend on the installed ctags build; CUDA extensions use its C++ parser.

**ctags reads saved files.** It does not resolve types, references, imports, or
rename symbols semantically. It provides no diagnostics, semantic tokens, LSP
hover/signature help, code actions, or snippets. Those Neovim LSP features are
absent from the standalone file; `gD` and `K` retain Vim's native behavior when no LSP server is configured. Files with embedded
newlines cannot be indexed by this line-oriented ctags integration.

## Interface, files, and search

| Key                                         | Action                                                                            |
| ------------------------------------------- | --------------------------------------------------------------------------------- |
| `<leader>A`                                   | Native dashboard; also appears on an empty interactive startup                    |
| Dashboard `j/k`, `Enter`                    | Select and run a menu item; letter keys also work                                 |
| Dashboard `:`                               | Close the overlay and start an Ex command; `:q` exits when no other window exists |
| `Space`                                     | Show a guide to actual Space mappings after the mapping timeout                   |
| `<leader>e`                                   | Toggle the editable file tree in a left sidebar                                                    |
| Tree `g?`                                   | Open shortcut help; `g?`, `q`, or `Esc` closes it; `j/k` and `Ctrl-d/u` scroll    |
| `<leader>f`, `<leader>Enter`                    | Find project files / Git-tracked files                                            |
| `<leader>st`, `<leader>t`                       | Live text search / search the cursor word or Visual selection; multiline selections require `rg` |
| `<leader>s/`                                  | Search the saved contents of open files                                           |
| `<leader>sr`, `<leader>sn`                      | Recent files / Vim configuration files                                            |
| `<leader>sb`, `<leader>bp`                      | Buffer picker                                                                     |
| `<leader>sc/sh/sp/sk`                         | Commands / help / themes / keymaps                                                |
| `Shift-h/l`, `[b` / `]b`, `Alt-1` … `Alt-9` | Switch buffers                                                                    |
| `<leader>bw`, `<leader>c`                       | Close buffer / force-close buffer, keeping split frames                           |
| `<leader>bm`, `<leader>bh/bl`                   | Close other buffers / buffers to the left or right                                |
| `<leader>bj/bk`, `<leader>bD/bL`                | Reorder buffers / sort by directory or language                                   |
| `<leader>Ti`                                  | Toggle indent guides (off by default)                                             |
| `<leader>Tr`                                  | Toggle relative line numbers in editor windows                                   |
| `<leader>Ts`                                  | Toggle Sticky Scroll (off by default)                                             |
| `<leader>TS`                                  | Toggle animated paging (off by default)                                           |
| `<leader>Tl`                                  | Toggle ctags/formatter status information                                         |

Pickers use native fuzzy matching, a preview, `Ctrl-n/p` or arrow keys to select,
`Enter` to open, `Esc` to close, and `Ctrl-q` to send matches to quickfix. Text
search uses `rg` when available, otherwise `grep`. File discovery uses `find`.
The keymap picker displays the configured prefix as `<leader>` rather than an
unlabelled space, and distinguishes global from buffer-local mappings.

The tree is an editable buffer: use `i/a` or `I/A` to edit a filename,
`cc/S` to replace it, `o` for a child entry and `O` for a sibling. A trailing
`/` creates a directory; `src/main.py` creates the directory and file together.
Use `yy` then `p` to copy an entry and give the copy a different name. `dd`
removes an entry; pasting a cut row next to a child of another directory moves it there.
`p/P` aligns pasted rows to the current depth and keeps them outside expanded
folder children when pasting next to the folder itself.
Directory membership follows two-space indentation. Press Esc and `:w` to
review and confirm the operations; editing the listing alone changes no files.
Duplicate destinations are rejected. Save folder copies/moves separately from
edits inside those folders, as in FLASH.
`u` undoes unsaved listing edits. Refresh or close offers Save/Discard/Cancel.

Enter or `za` expands/collapses directories and opens files in an editor window;
`zc` collapses a directory or its parent. `-` changes the root to its parent,
and `:Ntree /path` sets it explicitly. `gr` refreshes, `g.` toggles hidden entries,
`gs` selects sorting, and `gx` opens an entry with the system opener. Hidden and
Git-ignored entries are shown by default. `<LocalLeader>i` toggles ignored entries;
`<LocalLeader>w` uses the working directory as the root. `<LocalLeader>v/s/t`
opens a file in a vertical/horizontal split or tab, `<LocalLeader>p` previews it,
and `<LocalLeader>d/D` sets the global/tab working directory. The local leader
is Vim's default backslash unless configured otherwise. `Ctrl-c` closes the tree;
`g?` shows the key guide without changing window-navigation shortcuts.

Copies use the system `cp` command and run asynchronously before
moves or deletions begin. Existing destinations, changed source files, and
modified source buffers are refused. Failed operations attempt rollback;
backups are kept if rollback fails. The tree reads expanded directories only,
with a limit of 10,000 displayed rows, 40 levels and 200 operations per save.
Names containing tabs/newlines and paths through symlink parents are unsupported.

Project roots match ***FLASH***: Git/project markers for ordinary source,
the package directory inside `site-packages`/`dist-packages`, and the Python
standard-library directory identified by `os.py` plus `importlib/__init__.py`.
This does not hard-code a Python version.

Sticky Scroll uses the same bounded indentation-based heuristic as ***FLASH***,
including multiline Python function signatures. It preserves source line
numbers, the sign/number gutter, indent guides, and native syntax colors.
It shows at most eight scope lines; overflow keeps the outermost scope and
enclosing function, then nearby inner scopes. It is not a language parser and
may be incomplete in irregularly indented code or scopes beginning more than
1,000 lines above the viewport.

The active status line shows a mode-colored Git branch, filename, ctags and
formatter availability, filetype, and padded position. Inactive windows show
only filename and filetype. `[CTAGS X]` / `[FORMAT X]` means no supported tool was
found. Installing an executable does not add unsupported filetypes automatically.

## Git, formatting, sessions, and terminal

| Key                              | Action                                                                  |
| -------------------------------- | ----------------------------------------------------------------------- |
| `<leader>gg`                       | 90% × 90% lazygit popup if installed; otherwise native Git status split |
| `<leader>gd/gD`                    | Diff the editable buffer against the index / HEAD in a separate tab     |
| `<leader>gn/gp`                    | Next / previous changed hunk                                            |
| `<leader>gb`                       | Toggle inline blame (off initially, 150 ms delay)                       |
| `<leader>gs/gr`                    | Stage/reset the cursor hunk or selected Visual lines                   |
| `<leader>gS/gR`                    | Stage/reset the whole buffer                                          |
| `<leader>gU`                       | Undo the last staging action in this buffer                           |
| `<leader>gv`                       | Preview the cursor hunk                                               |
| `<leader>gt`                       | Toggle a popup showing deleted lines                                  |
| `<leader>gB`                       | Show blame and commit details for the current line                     |
| `ih`                              | Select the current hunk in Visual or Operator-pending mode             |
| `<leader>sg`                       | Recent commit log                                                       |
| `<leader>lf`                       | Format asynchronously; never automatically on save                      |
| `<leader>u`                        | Preview undo states, then apply the selected state                      |
| `<leader>pr/pl/pS/pd`              | Restore directory session / last session / pick session / stop saving   |
| `Ctrl-t`                         | Toggle the reusable bottom terminal split (`+terminal`)                 |
| `Ctrl-\` then `\` or `Ctrl-\` | Toggle the same terminal fullscreen from any window or mode             |
| `<leader>TT`                     | Stop the old shell and start a new one in the editor's `:pwd`           |
| Terminal `Esc Esc` or `Ctrl-w N` | Enter Terminal-Normal mode; `i` returns to terminal input               |

Hiding the terminal keeps its shell running and removes it from buffer lists.
Fullscreen uses a temporary tab and returns to the previous window. Editor zoom
and terminal fullscreen are restored before saving or loading a session.
`:qa` closes the reusable terminal with Vim; unsaved files still prevent quitting.
Vim checks buffers in order, so its shell may already stop before an unsaved file
cancels quitting.

Git signs include **unsaved** changes on Vim 9.0, using asynchronous snapshot
diffs. Cached index contents are reused while typing and refreshed on file
entry/save, focus return, or shell completion. Neither cursor movement nor
status-line redraw launches Git commands. Inline blame is a noninteractive
end-of-line popup, compatible with Vim 9.0 without virtual-text support; it is
hidden while editing modified contents. Closing either diff pane returns to the
original editing tab without changing its window settings.

Staging uses the current buffer, including unsaved edits. Reset changes the
buffer only and remains undoable. Staging and stage undo check for conflicting
changes to this file's staged contents. Hunk actions support regular UTF-8
text files up to 256 KiB; binary files, custom Git filters and working-tree
encoding conversions are rejected. New CRLF files need an initial `git add`.
`:NopackCancel` cancels pending reads but lets an index write finish safely.
Vim 9.0 uses popups for hunk/deleted-line previews instead of inserting virtual
lines into the editor.

Formatters are searched on **PATH, then existing Neovim Mason binaries**; Vim
never installs them. Python prefers Ruff, then Black. Other registrations match
***FLASH***: StyLua; clang-format for C/C++/CUDA/Proto; Prettier for JS/TS/React,
HTML/CSS/SCSS/Less, JSON/JSONC, YAML, Markdown/MDX, GraphQL, Vue, Handlebars;
Buildifier for Bazel; shfmt for Shell; cmake-format; latexindent for TeX; rustfmt.
MLIR has no standalone formatter registration. There is no LSP-format fallback.
Late formatter output is discarded if the buffer changed or was renamed.

Local desktop yanks use Vim's system clipboard when supported. SSH/default
terminal yanks use OSC52 plus `base64`, including tmux wrapping; the client
terminal must permit OSC52. This is **copy to the client**, not a remote read of
the client clipboard. Paste using the terminal's paste shortcut.

Large files disable expensive automatic features at 2 MiB / 50,000 lines.
Git signs and sticky scanning have lower byte limits, signs are capped at 2,000,
and background commands have time/output limits. Complex mixed Git hunks use
coarse added/changed classification to bound UI-thread work; changed ranges remain visible.
Formatter work, indexing, and
Git commands run asynchronously. Caches are tied to edits and lifecycle events,
not arbitrary expiration timers.
