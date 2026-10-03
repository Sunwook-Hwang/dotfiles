# Plugin-free Vim — Vim 9.0+

[한국어](plugin-free-vim.ko.md) · [Configuration](../vim/.vimrc) · [Neovim counterpart](flash.md)

One `.vimrc`, native Vimscript, **no third-party plugins, no plugin manager, no
Lua, no startup downloads**. Vim's bundled runtime supplies syntax highlighting,
filetype indentation, netrw, completion, diff, terminals, and popup windows.

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

Caches, persistent undo, netrw state, and sessions are stored under
`~/.vim/nopack`. Set `VIM_NOPACK_DATA` before starting Vim to change this
directory. Third-party directories are excluded from `runtimepath` and
`packpath`, so an existing Vim plugin installation is not loaded.

## Editing and navigation

The leader key defaults to Space; `<leader>` below refers to that key.

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
| Visual `*` / `#`                                                | Search the selected text literally, forward / backward, preserving registers |
| `[Space` / `]Space`                                             | Add blank lines above / below; supports counts, undo, and `.`                |
| `[q` / `]q`, `[l` / `]l`, `[a` / `]a`, `[t` / `]t`              | Previous / next quickfix item, location item, argument, or tag match         |
| `[Q` / `]Q`, `[L` / `]L`, `[A` / `]A`, `[T` / `]T`, `[B` / `]B` | First / last item in those lists or the buffer list                          |
| `>>` / `<<`                                                     | Shift the current line right / left, including first-column Python comments  |
| Visual `>` / `<`                                                | Shift selected lines and keep the selection for repeated shifts              |
| `Ctrl-s`                                                        | Save from Normal or Insert mode                                              |
| `jk`                                                            | Leave Insert mode                                                            |
| `Ctrl-h/j/k/l`                                                  | Move between windows                                                         |
| `Alt-j/k`                                                       | Move the current line or selection down / up                                 |
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
LSP/diagnostic/Tree-sitter mappings are not emulated.

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
deliberately absent; `gD` and `K` retain Vim's native behavior. Files with embedded
newlines cannot be indexed by this line-oriented ctags integration.

## Interface, files, and search

| Key                                         | Action                                                                            |
| ------------------------------------------- | --------------------------------------------------------------------------------- |
| `<leader>A`                                   | Native dashboard; also appears on an empty interactive startup                    |
| Dashboard `j/k`, `Enter`                    | Select and run a menu item; letter keys also work                                 |
| Dashboard `:`                               | Close the overlay and start an Ex command; `:q` exits when no other window exists |
| `Space`                                     | Show a guide to actual Space mappings after the mapping timeout                   |
| `<leader>e`                                   | Toggle netrw in a left sidebar                                                    |
| Tree `g?`                                   | Open shortcut help; `g?`, `q`, or `Esc` closes it; `j/k` and `Ctrl-d/u` scroll    |
| `<leader>f`, `<leader>Enter`                    | Find project files / Git-tracked files                                            |
| `<leader>st`, `<leader>t`                       | Live text search / search the cursor word                                         |
| `<leader>s/`                                  | Search the saved contents of open files                                           |
| `<leader>sr`, `<leader>sn`                      | Recent files / Vim configuration files                                            |
| `<leader>sb`, `<leader>bp`                      | Buffer picker                                                                     |
| `<leader>sc/sh/sp/sk`                         | Commands / help / themes / keymaps                                                |
| `Shift-h/l`, `[b` / `]b`, `Alt-1` … `Alt-9` | Switch buffers                                                                    |
| `<leader>bw`, `<leader>c`                       | Close buffer / force-close buffer, keeping split frames                           |
| `<leader>bm`, `<leader>bh/bl`                   | Close other buffers / buffers to the left or right                                |
| `<leader>bj/bk`, `<leader>bD/bL`                | Reorder buffers / sort by directory or language                                   |
| `<leader>Ti`                                  | Toggle indent guides (on by default)                                              |
| `<leader>Ts`                                  | Toggle Sticky Scroll (off by default)                                             |
| `<leader>TS`                                  | Toggle animated paging (off by default)                                           |
| `<leader>Tl`                                  | Toggle ctags/formatter status information                                         |

Pickers use native fuzzy matching, a preview, `Ctrl-n/p` or arrow keys to select,
`Enter` to open, `Esc` to close, and `Ctrl-q` to send matches to quickfix. Text
search uses `rg` when available, otherwise `grep`. File discovery uses `find`.

netrw supports Enter/`l`, `h`, `-`, `o/v/t`, `%` (create a file in the editor),
`d`, `D`, `R`, `mf`, `mu`, `mt`, `mc`, `mm`, and `<leader>nr`. Copy/move requires
the system `cp`/`mv` commands. Destructive actions use the resolved tree path;
ambiguous decorated names are refused. Refresh stays inside the existing tree.
Use `:Ntree /path` or `gn` in the tree to set its root manually.

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
| `<leader>sg`                       | Recent commit log                                                       |
| `<leader>lf`                       | Format asynchronously; never automatically on save                      |
| `<leader>u`                        | Preview undo states, then apply the selected state                      |
| `<leader>pr/pl/pS/pd`              | Restore directory session / last session / pick session / stop saving   |
| `Ctrl-t`                         | Toggle the reusable bottom terminal split (`+terminal`)                 |
| Terminal `Esc Esc` or `Ctrl-w N` | Enter Terminal-Normal mode; `i` returns to terminal input               |

Hiding the terminal keeps its shell running and removes it from buffer lists.
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
