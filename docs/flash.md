# ***FLASH*** — Native Neovim Guide

`<leader>` means your configured leader key. The default is Space; change it in `lua/options.lua` or set `vim.g.mapleader` before loading ***FLASH***. An existing value is preserved.


[English](flash.md) | [한국어](flash.ko.md)

`nvim/.config/nvim/init.lua` is a **package-free, native Neovim configuration** organized
into feature modules for Neovim 0.12+. It has no plugin manager, no external Lua
plugins, and no parser download step. It uses only Neovim's built-in APIs,
bundled runtime, and system commands that are already installed.

***FLASH*** uses this repository's [Package-based Neovim configuration](package-based-neovim.md)
as its **functional reference** for core features, shortcuts and editing workflow.
It implements those capabilities with native APIs; individual interfaces and behavior
can differ. Bundled theme definitions are adapted from the upstream repositories
listed in [theme sources, licenses and adaptation notes](../nvim/.config/nvim/lua/themes/README.md),
without requiring their plugins at runtime.

LSP servers and formatters are optional executables. The configuration detects
the tools it knows about but never downloads, installs, or updates them.

- Configuration: `nvim/.config/nvim/init.lua` and its adjacent `lua/` and `colors/` directories
- Required version: Neovim 0.12 or newer

Contents:

- [Starting Neovim and the dashboard](#starting-neovim-and-the-dashboard)
- [Interface](#interface)
- [Native leader-key guide](#native-leader-key-guide)
- [Files and buffers](#files-and-buffers)
- [Search and picker UI](#search-and-picker-ui)
- [Git](#git)
- [LSP, completion, and diagnostics](#lsp-completion-and-diagnostics)
- [Formatting](#formatting)
- [Undo, sessions, and terminal](#undo-sessions-and-terminal)
- [Editing conveniences](#editing-conveniences)
- [Performance and safety limits](#performance-and-safety-limits)
- [Deliberately unsupported](#deliberately-unsupported)
- [Tool setup and server transfer](#tool-setup-and-server-transfer)
- [Ctags fallback](#ctags-fallback)
- [Configuration structure](#configuration-structure)

## Starting Neovim and the dashboard

```sh
NVIM_APPNAME=nvim nvim
```

Starting without a file opens a native dashboard. Move with `j/k` or the arrow
keys and press `Enter`. The cursor stays on selectable rows.

| Key       | Action                               |
| --------- | ------------------------------------ |
| `f`       | Find project files                   |
| `r`       | Open recent files                    |
| `l`       | Restore the last session             |
| `p`       | Select a saved session               |
| `n`       | Create a new file                    |
| `c`       | Open the active Neovim configuration |
| `q`       | Quit                                 |
| `<leader>A` | Reopen the dashboard while editing   |

Passing a file argument skips the dashboard and opens that file directly.

The dashboard uses a dedicated floating window. `Esc` closes it without changing
the underlying editor's buffer, cursor, scroll position, or window options.
Menu actions and direct `:edit` commands open files in the original editor window.

## Interface

### Status line

The left side shows the Git branch and state followed by the filename. The
right side shows diagnostics, LSP and formatter availability, filetype, and a
fixed-width cursor position.

```text
[master .M] file.lua [+]    E: 1 W: 2 [LSP: lua_ls] [FORMAT: stylua] lua |  123:  8 |  42%
```

- Diagnostic groups with a count of zero are hidden.
- Without LSP, supported ctags is shown as `[CTAGS: Universal]` or `[CTAGS: Exuberant]`; otherwise `[LSP X]` has a highlighted background.
- `[FORMAT X]` means no formatter is currently available.
- `[FORMAT: name]` names the external formatter or LSP used for this buffer.
- `<leader>Tl` toggles both the LSP and formatter status sections.
- `<leader>Td` toggles native statusline breadcrumbs (`path > class > function`) from cached LSP symbols; click a symbol to jump to its declaration. Without symbol support, only the path is shown. No code-text or indentation guesses are used.

### Buffers, indent guides, and Sticky Scroll

- The native tabline displays open buffers and modified state.
- `Alt-1..8` selects that numbered buffer; `Alt-9` selects the last buffer.
- Indent guides use `┊` and follow the file's `shiftwidth`.
- Sticky Scroll is off by default and keeps up to eight enclosing function, conditional, and loop lines when enabled.
- Sticky rows preserve real line numbers, indentation, syntax highlighting, and a separator.
- `<leader>Ti` toggles indent/whitespace markers; `<leader>Ts` toggles Sticky Scroll.

`Ctrl-d` / `Ctrl-u` animate half-page scrolling in roughly 120 ms, including
wrapped lines and folds. `<leader>TS` (uppercase `S`) toggles the animation; it is
disabled by default. Diff, floating/special buffers, large files, bound windows,
and macro recording/playback use native scrolling immediately.

Sticky Scroll is a syntax-and-indentation heuristic. It scans at most 1,000
lines or 256 KiB above the viewport. Unusual language syntax and complex
multiline declarations can still be missed.

## Native leader-key guide

Pressing your leader key in Normal mode opens a native guide for the available
leader mappings. Buffer-local LSP and explorer mappings appear only when applicable.

- Continue typing to close the guide and run the selected mapping.
- `Esc`, `Ctrl-c`, or an unmapped key cancels it.
- Quickly completed mappings run without waiting for the guide.
- It does not intercept Visual, Insert, or Terminal mode.

## Files and buffers

| Key                    | Action                                                    |
| ---------------------- | --------------------------------------------------------- |
| `<leader>f`              | Fuzzy-find project files                                  |
| `<leader><CR>`          | Find Git-tracked files                                    |
| `<leader>e`              | Toggle the editable file explorer       |
| `<leader>sb`             | Select an open buffer                                     |
| `<leader>sr`             | Select a recent file                                      |
| `<leader>sn`             | Find Neovim configuration files                           |
| `Shift-h/l`, `[b`/`]b` | Previous/next buffer                                      |
| `<leader>bj/bk`          | Move the current buffer in the tabline                    |
| `<leader>bD/bL`          | Sort buffers by directory/filetype                        |
| `<leader>bp`             | Select a buffer                                           |
| `<leader>bw`             | Close the current buffer while protecting unsaved changes |
| `<leader>c`              | Force-close the current buffer                            |
| `<leader>bm`, `<leader>be` | Close other safe buffers                                  |
| `<leader>bh/bl`          | Close safe buffers to the left/right                      |

These buffer-close mappings preserve split windows and their sizes while multiple
buffers remain. When only one buffer remains, its duplicate editor panes in the
current tab merge into one; sidebars, floats, and other tabs are preserved.
Closing the last buffer leaves an empty buffer.

The Git root is the preferred project root. Without Git, the configuration
searches upward for CMake, Make, package.json, Python, Cargo, Bazel, and Buf
project markers. The editor cwd, search, LSP, and ctags share this root. The explorer
starts at this root and expands the path to the current file.
For installed Python libraries, the top-level package under `site-packages` or
`dist-packages` is the root (for example, `site-packages/tvm`). Git discovery
stops at that package boundary, so a parent Homebrew or project repository is
not used. Git repositories inside the package are still recognized. A standalone
module directly in `site-packages` or `dist-packages` uses that directory instead.
Python standard-library files use the directory containing both `os.py` and
`importlib/__init__.py` (for example, `lib/python3.13`). Installed packages take
precedence over this enclosing standard-library root; neither crosses into a
parent repository.

### Editable file explorer

`<leader>e` opens a native expandable tree without line numbers on the left, starting at the project
root and expanding the path to the current file. No Oil plugin or other package is needed. Like Oil, edit the
listing with normal Vim commands, then use `:w` and confirm the operations.

| Key | Action |
| --- | --- |
| `Enter` / `za` | Open the file in an editor or expand/collapse the folder |
| `zc` | Collapse the folder or its parent |
| `-` / `\w` | Parent / working directory |
| `\v` / `\s` / `\t` | Open in a vertical split / horizontal split / tab |
| `\p` | Toggle file preview |
| `Ctrl+c` | Close the explorer and return to an editor |
| `gr` | Refresh the listing |
| `g.` | Toggle hidden files (shown by default) |
| `\i` | Toggle Git ignored files (shown by default) |
| `gs` | Choose name/size/mtime and ascending/descending order |
| `\d` / `\D` | Set global / tab working directory |
| `gx` | Open in an external application |
| `g?` | Toggle explorer help, including after returning to edit the tree |
| `yy` → `p`, rename pasted row, `:w` | Copy a file or directory |
| `i` / `a` | Edit the filename at / after the cursor |
| `I` / `A` | Edit at the start / end of the filename |
| `cc` | Replace the entire filename |
| Edit a filename, `Esc`, `:w` | Confirm the rename without changing file contents |
| `o`, type a filename, `:w` | Create an empty file; append `/` for a directory |
| `dd`, `:w` | Delete the file or directory after confirmation |

To create a folder, press `o`, type `src/`, then press `Esc`, run `:w` and confirm.
Without the trailing `/`, `src` creates an empty file. Keep the `/` suffix when
renaming a folder. On any folder row, `o` creates a child automatically and expands
existing collapsed folders. `O` creates an entry above at the same depth.
Type `test/main.py` to create both the missing `test` folder and its file in one
save; `a/b/` creates nested folders. Paths are relative to the row's containing
folder. A new folder row and its children can also be saved together. Absolute
paths and `.` / `..` components are rejected.

`yypp` pastes two copies of the entry; give each a distinct name before saving.
`cc`, `S`, and `I` preserve the concealed file identity column. Duplicate names,
existing destinations, and externally changed source files are rejected before
saving. Unsaved directory edits prompt Save / Discard / Cancel when navigating.
Use `Ctrl+h/j/k/l` or `Ctrl+w h/j/k/l` to move between windows.
`Ctrl+s` still saves and `Ctrl+t` still toggles the terminal. Explorer-only
commands use LocalLeader (default `\`); `h/l` retain normal cursor movement.

`g?` toggles a single help window from either the tree or the help window.
Inside help, `q`, `Esc`, or `Ctrl+c` closes it. Closing or hiding its owner tree
also closes help. The help window cannot be reused as a source editor.
Hidden and Git ignored entries are shown by default and can be toggled separately.
Git ignore checks run asynchronously in batches and reuse cached results until
refresh; hiding an entry does not schedule its deletion when saving.

Copy and recursive cleanup use asynchronous native filesystem calls. While `:w`
is running, directory listings are temporarily read-only and a second save is
rejected; source editor buffers remain editable. Unchanged listings are not
rewritten. Hidden clean directory buffers are released, while unsaved listings
and copied file identities are retained. Renames preserve open source buffers and
unsaved text; deletion rejects modified source buffers and removes clean stale
buffers through the normal buffer-close policy.

Folders expand below their row. Expansion reads only the selected folder; collapse
and re-expansion reuse its listing until refresh, reopen or save. Vertical guides
show the tree depth without `+`/`-` markers or line numbers. Guides update after
listing edits and undo without scanning directories. `o` inserts a child under a folder; pastes use the selected
row's depth. Collapse a folder before `dd`, or select its complete visible subtree.
Save renames/deletions of a folder separately from other edits inside it;
creating a folder and its children together is supported. Directory symlinks open
as a separate root to avoid recursive cycles. Local files, recursive directory
copies and symlinks are supported. Trash/SSH adapters, permission
columns, overwrite and cyclic rename operations are not implemented. Undo edits
in the listing before saving; filesystem operations are not an undo history.

The margin retains Git index/worktree status: `.M` is a saved modification, `M.`
is staged, `??` is untracked, and `**` marks mixed directory contents.

## Search and picker UI

A shared native picker provides an input box, result list, and preview without Telescope.

| Key        | Action                                          |
| ---------- | ----------------------------------------------- |
| `<leader>st` | Live project regex search                       |
| `<leader>t`  | Search for the cursor word, then filter results |
| `<leader>s/` | Search the saved on-disk contents of open files |
| `<leader>sc` | Find commands                                   |
| `<leader>sh` | Find help tags                                  |
| `<leader>sk` | Find current keymaps                            |
| `<leader>sp` | Preview and select a colorscheme                |
| `<leader>sd` | Find all diagnostics                            |

In a picker, use `Ctrl-n/p` or `Tab/Shift-Tab` to select, `Enter` to apply,
`Esc` to cancel, and `Ctrl-q` to export results to quickfix. Search prefers `rg`
and falls back to `grep` or `find`.

The colorscheme picker also includes native snapshots of TokyoNight, Catppuccin,
Kanagawa, Everforest, Nightfox, Rose Pine and GitHub themes, with the same 38 names
available in the package profile, plus Ayu (`ayu`, `ayu-dark`, `ayu-mirage`, `ayu-light`).
Only the selected color definitions are loaded;
no theme plugin, compiler cache or download is needed. The default remains `retrobox`.
Dark/light variants follow the selected theme's original behavior. Upstream setup
APIs and dynamic integrations are not included. [Sources and licenses](../nvim/.config/nvim/lua/themes/README.md)
are retained with the snapshots.

## Git

Git features never run network commands. Unsaved changes are compared with the
index and shown as `+`, `~`, and `-` signs in the margin.

| Key           | Action                                                                      |
| ------------- | --------------------------------------------------------------------------- |
| `<leader>gg`    | Open lazygit in a 90% × 90% float; otherwise show native Git status                                |
| `<leader>sg`    | Browse recent commits                                                       |
| `<leader>gd`    | Editable current file beside the index; `:q` in either pane closes the diff |
| `<leader>gD`    | Editable current file beside HEAD; `:q` in either pane closes the diff      |
| `<leader>gn/gp` | Move to the next/previous change hunk, wrapping at the ends                 |
| `<leader>gb`    | Toggle inline blame for the current line                                    |

Inline blame shows the author, date, and commit subject at the end of the current
line after 150 ms of inactivity. It hides during unsaved edits to avoid incorrect
line attribution and returns after saving. It is disabled for large files.

Additional editing actions use the same keys as Package-based Neovim:

| Key | Action |
| --- | --- |
| `<leader>gs/gr` | Stage/reset the cursor hunk or selected Visual lines |
| `<leader>gS/gR` | Stage/reset the whole buffer |
| `<leader>gU` | Undo the last staging action in this buffer |
| `<leader>gv` | Inline hunk preview; clear on cursor movement or editing |
| `<leader>gt` | Toggle deleted lines |
| `<leader>gB` | Full blame with commit details |
| `ih` | Hunk text object, including `vih` and `dih` |

Staging includes unsaved edits; reset changes the buffer against the index without
writing the file. Staging undo refuses to overwrite intervening changes to the
same index file entry. Hunk actions support regular UTF-8 text files up to 256 KiB;
conflicted index entries and binary files are rejected. Once an index write begins,
`:NopackCancel` lets it finish so Git can release its lock normally.

## LSP, completion, and diagnostics

Python editing uses native LSP/buffer completion and does not require a `pynvim`
Python host. FLASH disables automatic Python-host probing to avoid synchronous
interpreter searches when Python files open. If you need Neovim's separate `:python3`
interface, set `vim.g.python3_host_prog` before loading FLASH to opt in. This does
not disable Python executables, ty/Pyright, or Python formatters.

Only configured servers whose executables can be found are started. Executables
are searched in this order:

1. the current `PATH`
2. an existing `stdpath("data")/mason/bin`

Mason is never loaded and no tool is installed automatically.

| Language                      | Server                                                       |
| ----------------------------- | ------------------------------------------------------------ |
| C/C++/Objective-C/CUDA        | `clangd`                                                     |
| MLIR                          | `mlir-lsp-server`                                            |
| Python                        | `ty server`, falling back to `pyright-langserver`            |
| Lua                           | `lua-language-server`                                        |
| JavaScript/TypeScript/JSX/TSX | `typescript-language-server`                                 |
| HTML                          | `vscode-html-language-server`                                |
| CSS/SCSS/Less                 | `vscode-css-language-server`                                 |
| Bazel/Starlark                | `starpls server`                                             |
| Protocol Buffers              | `buf lsp serve`                                              |
| Shell                         | `bash-language-server start`                                 |
| CMake                         | `neocmakelsp stdio`, falling back to `cmake-language-server` |
| YAML                          | `yaml-language-server`                                       |
| TeX                           | `texlab`                                                     |
| Rust                          | `rust-analyzer`                                              |
| Web auxiliaries               | Tailwind, Svelte, GraphQL, Emmet, Prisma, ESLint             |

Tailwind and ESLint attach only when project configuration or dependencies are
present. Emmet requires a project marker. An arbitrary executable for an unknown
language is not attached automatically.

| Key                | Action                                                  |
| ------------------ | ------------------------------------------------------- |
| `Ctrl-Space`       | Request completion manually in Insert mode              |
| `Ctrl-n/p`         | Select completion candidates                            |
| `Enter`            | Confirm a selected candidate or insert a normal newline |
| `Tab`, `Shift-Tab` | Move through snippet stops or candidates                |
| `gd`               | LSP definition, then ctags fallback                     |
| `gr`, `gD`, `K`    | References, declaration, hover documentation            |
| `gR`, `gi`, `gt`   | References/implementation/type-definition picker        |
| `<leader>la/lr`      | Code action/rename                                      |
| `<leader>ls`         | Restart LSP clients attached to this buffer             |
| `<leader>lv`         | Select a Python analysis environment                    |
| `[d`, `]d`         | Previous/next diagnostic                                |
| `<leader>ld/lD/sd`   | Line/buffer/all diagnostics                             |
| `<leader>lt`         | Toggle diagnostic display                               |
| `<leader>o`          | LSP or ctags code outline                               |

Completion opens automatically while typing in analysis-eligible buffers. With
LSP, identifier input and server trigger characters request candidates;
`Ctrl-Space` can also request them explicitly.

Without LSP, built-in completion uses words from the current and open buffers
plus ctags symbols. When supported ctags is installed, `gd` and the outline fall
back to saved sources in languages supported by the installed ctags. Use `:checkhealth vim.lsp` to inspect LSP state.

The outline and editor track each other without moving focus or requesting symbols on cursor movement. LSP tracking selects the innermost enclosing symbol; ctags tracking uses the nearest preceding declaration because it has no scope ranges.

Inside the outline, `r` refreshes and `q` closes it. `Enter` jumps to the selected
symbol and moves focus to the editor.

## Formatting

`<leader>lf` formats the unsaved current buffer asynchronously. External output is
compared with `vim.text.diff()` and only changed ranges are applied, as one undo
step. Results are discarded if the buffer changes or closes while formatting.

| Filetype                           | External formatter                     |
| ---------------------------------- | -------------------------------------- |
| Lua                                | `stylua`                               |
| C/C++/CUDA                         | `clang-format`                         |
| Python                             | `ruff format`, falling back to `black` |
| JS/TS/JSX/TSX, HTML, CSS/SCSS/Less | `prettier`                             |
| JSON/JSONC, YAML, Markdown/MDX     | `prettier`                             |
| GraphQL, Vue, Handlebars           | `prettier`                             |
| Bazel/Starlark                     | `buildifier`                           |
| Protocol Buffers                   | `clang-format`                         |
| Shell                              | `shfmt`                                |
| CMake                              | `cmake-format`                         |
| TeX                                | `latexindent`                          |
| Rust                               | `rustfmt`                              |

If no registered external formatter exists, an attached LSP with document
formatting support is used. No external formatter is registered for MLIR or
Zsh. Format-on-save and range formatting are disabled.

## Undo, sessions, and terminal

***FLASH*** and Package-based Neovim share persistent undo at
`${XDG_STATE_HOME:-$HOME/.local/state}/nvim/undo`. Saved file history remains
available when switching configurations; live editing sessions do not merge their undo trees.

| Key                | Action                                             |
| ------------------ | -------------------------------------------------- |
| `<leader>u`          | Preview undo states and apply the selected state   |
| `<leader>pr`         | Restore the current project session                |
| `<leader>pl`         | Restore the last session                           |
| `<leader>pS`         | Select a saved session                             |
| `<leader>pd`         | Stop saving the session for this run               |
| `Ctrl-t`           | Toggle a reusable shell terminal in a bottom split |
| Terminal `Esc Esc` | Leave Terminal mode                                |

***FLASH*** and Package-based Neovim share sessions at
`${XDG_STATE_HOME:-$HOME/.local/state}/nvim/sessions`, one per working directory.
Sessions preserve named editing files, cursor positions, cwd, splits, and tabs.
Explorer, help, floating windows, terminals, folds, and profile options are not
restored. Sessions
are not backups of unsaved file contents. The last editor to save a project wins.

Sessions are **saved automatically when Neovim exits** if a named source buffer
exists. `<leader>pd` disables saving for this run without deleting existing sessions.

On Neovim 0.13 development builds, `:restart` and `ZR` use the same auxiliary-buffer
filter as normal session saves. `:restart!` skips restoration, as defined by Neovim.
`Q`, `.`, and Insert-mode cursor keys follow the installed Neovim version's native
behavior without compatibility mappings. `autoread` stays enabled, but the new per-buffer
file watchers are disabled to retain 0.12's focus-change/`:checktime` updates,
including on NFS. Unsaved edits are not silently replaced. No polling timer is added.

Keep the terminal open while moving between windows with `Ctrl-h/j/k/l`;
Shift-arrow resizing also works in Terminal input mode. Press `Esc Esc` or
`Ctrl-\` followed by `Ctrl-n` to enter Terminal Normal mode, navigate output with
`hjkl` or `Ctrl-u/d`, and copy with `y`. Press `i` to resume shell input. Hiding
the terminal with `Ctrl-t` keeps its shell running; this does not keep jobs alive
after Neovim itself exits.

## Editing conveniences

Comment toggling uses Neovim's built-in support without a plugin. It needs a
valid `commentstring` for the filetype; inspect `:set filetype? commentstring?`
if commenting does not work.

| Key | Action |
| --- | --- |
| `gcc` | Toggle the current line's comment |
| Visual `gc` | Toggle comments on selected lines; e.g. select lines with `V`, then `gc` |
| Visual `>` / `<` | Indent / unindent the selection and keep it selected |
| `<leader>a` | Select the entire file |
| `<leader>Th` | Toggle highlighting other occurrences of the cursor word; off by default |
| `<leader>Sa` | Prepare substitution of the cursor word or Visual selection throughout the file |
| `<leader>Sf` | Prepare the same substitution from the current line to the end |
| Normal `Esc` | Clear search highlighting |
| Normal `+` / `-` | Increment / decrement a number |
| `jk` | Leave Insert mode |
| `Ctrl-s` | Save |
| `Alt-j/k` | Move the current line or Visual selection |
| `Ctrl-h/j/k/l` | Move between windows in Normal or Terminal mode |
| Insert `Alt-arrow` | Leave Insert mode and move to the window in that direction |
| Shift-arrow | Resize by five rows/columns in Normal or Terminal mode |
| `<leader>w` | Enable diff in all windows of the current tab; clear with `:windo diffoff` |
| Visual `p` / `P` | Replace the selection while preserving the copied text |
| Normal `x` | Delete a character without overwriting the yank register |

Substitution keys prepare a command rather than executing it. Type the replacement
and closing `/`, optionally add `g` (all matches per line) or `c` (confirm), then Enter.

Brackets, braces, quotes, and backticks pair automatically; Backspace removes both
characters of an empty pair. Search `n`/`N` keeps results centered, and copied text
is briefly highlighted.

Outside SSH and herdr, Windows, macOS, and Linux sessions use `unnamedplus` with
Neovim's desktop clipboard provider. In SSH or herdr, `yy` and Visual `y` send text to the viewing terminal
via OSC52 (which the terminal must support and allow); `p` uses the local register
without requesting clipboard access. Paste text from other applications using
the terminal's paste shortcut.

## Performance and safety limits

| Area                      | Limit                                           |
| ------------------------- | ----------------------------------------------- |
| General external commands | 5 seconds and 2 MiB stdout by default           |
| File/search candidates    | 10,000                                          |
| Displayed results         | 200                                             |
| File preview              | First 64 KiB                                    |
| Git signs                 | 256 KiB, 20,000 lines, 2,000 signs              |
| Formatting                | Files up to 2 MiB                               |
| Sticky Scroll             | 1,000 preceding lines, 256 KiB                  |
| Large-file protection     | Over 2 MiB, 50,000 lines, or a 10,000-byte line |
| SSH OSC52 copy            | Over 100,000 bytes is skipped with a warning    |

Large files disable LSP, syntax, completion, ctags, Git signs, Sticky Scroll,
formatting and cursor crosshair highlighting. The wrap setting is preserved. `:NopackCancel` cancels
running search, Git, and ctags jobs plus scheduled refreshes.

## Deliberately unsupported

- Automatic plugin, LSP, or formatter download and updates
- `todo-comments.nvim`-style TODO/FIXME highlighting
- Theme-plugin setup APIs and dynamic plugin integrations (native color snapshots are bundled)
- Neovide-specific font and zoom controls
- Debug Adapter Protocol (DAP)
- Automatic Treesitter parser installation

These are outside ***FLASH***'s scope because they add network
dependencies, platform-specific behavior, worktree mutation, or maintenance cost.

## Tool setup and server transfer

Install only the executables needed for the languages listed above. ***FLASH*** never
installs tools. Shell aliases do not count as executables; use real files,
symlinks, or launchers. Each configured candidate is searched in PATH, then the
existing Mason bin directory: for example, ty in Mason still wins over Pyright
in PATH. The installer shares Package-based Neovim's Mason tools with ***FLASH*** without loading Mason.

A portable layout is `~/.local/opt/nvim-tools/`, with `node-tools/`, `python/`,
`llvm/`, and `lua-language-server/` below it. Put standalone binaries or launchers
in `~/.local/bin`. Add the required executable directories to PATH:

```sh
# Bash / Zsh
export PATH="$HOME/.local/bin:$HOME/.local/opt/nvim-tools/node-tools/node_modules/.bin:$HOME/.local/opt/nvim-tools/python/bin:$PATH"
```

```csh
# Csh / Tcsh
setenv PATH "$HOME/.local/bin:$HOME/.local/opt/nvim-tools/node-tools/node_modules/.bin:$HOME/.local/opt/nvim-tools/python/bin:$PATH"
```

Add LLVM, StyLua, or a separately unpacked Node runtime's `bin` directory when
needed, then start Neovim from that shell. A running editor does not inherit
later changes to its parent shell's PATH.

### Preparing tools

Python defaults to ty and Ruff. Put compatible `ty` and `ruff` executables in
PATH. Pyright and Black are alternatives; Node.js is required for Pyright:

```sh
npm install --prefix "$HOME/.local/opt/nvim-tools/node-tools" --save-exact pyright
python3 -m venv "$HOME/.local/opt/nvim-tools/python"
"$HOME/.local/opt/nvim-tools/python/bin/python" -m pip install black
```

For web development, install `typescript-language-server` together with a
compatible `typescript` version, `vscode-langservers-extracted`, and `prettier`
in that Node tools directory. Preserve the generated lock file and choose
versions compatible with the target Node runtime. `tsserver` found in PATH or
Mason is supplied as `tsserver.fallbackPath`; the language server also handles
project/bundled TypeScript discovery. Copying only the language-server executable
is insufficient. Project `node_modules/.bin` is not searched automatically.

Other web server package names:

| Executable | npm package |
| --- | --- |
| `tailwindcss-language-server` | `@tailwindcss/language-server` |
| `svelteserver` | `svelte-language-server` |
| `graphql-lsp` | `graphql-language-service-cli` |
| `emmet-ls` | `emmet-ls` |
| `prisma-language-server` | `@prisma/language-server` |
| `vscode-eslint-language-server` | `vscode-langservers-extracted` |

For C/C++/CUDA, install both clangd and clang-format. Preserve LLVM's distribution
layout, including libraries. Accurate analysis needs project compilation flags;
CMake can produce them with `cmake -S . -B build -DCMAKE_EXPORT_COMPILE_COMMANDS=ON`.
LuaLS also needs its complete distribution, including `main.lua` and resources;
keep it intact and expose its launcher through PATH. StyLua is a separate tool.

### Network-isolated servers

Copy **`init.lua` and its adjacent `lua/` and `colors/` directories together** into
`~/.config/nvim/`, or run `nvim -u /path/to/init.lua`. No plugin directory or `vim.pack`
lock file is needed for ***FLASH***. Tool binaries must match the server's OS, CPU,
libc, and runtime requirements; macOS binaries and virtual environments cannot
be reused on Linux.

Transfer Node tools as a complete directory, preserving symlinks and dependencies:

```sh
# Connected preparation machine with a compatible platform/runtime
tar -czf nvim-node-tools.tar.gz -C "$HOME/.local/opt/nvim-tools" node-tools
# After transferring the archive to the server
mkdir -p "$HOME/.local/opt/nvim-tools"
tar -xzf nvim-node-tools.tar.gz -C "$HOME/.local/opt/nvim-tools"
```

Node.js must also be available on the server. Do not copy only `.bin` or run
`npm install` on a server without access to the registry. Keep LuaLS and LLVM
bundles intact too. For Python tools, download wheels and their dependencies
in a compatible environment, then create a fresh venv on the server:

```sh
# Connected machine; transfer wheelhouse/ to the server afterwards
python3 -m pip download --only-binary=:all: --dest wheelhouse black
# Server
python3 -m venv "$HOME/.local/opt/nvim-tools/python"
"$HOME/.local/opt/nvim-tools/python/bin/python" -m pip install --no-index --find-links=wheelhouse black
```

### Python environments and troubleshooting

`<leader>lv` selects the project's analysis environment: `.venv`, `venv`, active
virtualenv/Conda, PATH Python, discovered Conda environments, or a manually entered
environment directory/Python executable. `Automatic` resets the choice. Selection
lasts for this Neovim run and affects analysis, not the shell or formatter PATH.
Ty restarts affected project clients when the environment changes; Pyright receives
its Python path setting. Project Pyright venv configuration can override it.

If tools are missing, restart Neovim after installing them and check:

```vim
:messages
:set filetype?
:checkhealth vim.lsp
:lua vim.print(vim.lsp.get_clients({bufnr=0}))
:lua print(vim.fn.exepath('ty'))
:lua print(vim.fn.stdpath('data') .. '/mason/bin')
```

After external project configuration or tool changes, `:NopackRefresh` refreshes
project roots and formatter availability. Restart Neovim to register newly
available LSP servers.

`exepath()` checks PATH only, not ***FLASH***'s Mason fallback. A connected server can
still report import errors if the selected Python environment lacks dependencies.
Large-file protection also deliberately disables LSP and formatting.

## Ctags fallback

Universal Ctags is preferred; Exuberant Ctags is supported. BSD/Emacs ctags is not.
Check `ctags --version`. To select a binary explicitly:

```sh
nvim --cmd "let g:nopack_ctags='/path/to/ctags'"
```

| Key / command | Action |
| --- | --- |
| `gd` | Try LSP, then ctags; build the project index on first fallback |
| `g Ctrl-t` | Return through the tag stack |
| `:CtagsUpdate` | Rebuild the current project's index |
| `:CtagsClearAll` | Delete all managed project tag caches |
| `:NopackCancel` | Cancel jobs and pending refreshes |

Completion without an LSP and the ctags outline index the current file on demand.
Used project indexes update saved files after a 750 ms debounce; external file
changes require `:CtagsUpdate`. Git projects include tracked and non-ignored
untracked files. Caches live in `stdpath('data')/nopack/tags/`; `:setlocal tags?`
shows attached tag files. Full indexing is limited to 120 seconds/64 MiB and
file updates to 10 seconds/16 MiB. Ctags indexes saved names and positions;
it cannot replace semantic type analysis or track unsaved changes accurately.

## Live buffer sharing

***FLASH*** can share one editable text buffer across independent Neovim processes,
including different nodes that store the source on NFS. No plugin or external
server executable is used. NFS stores the file; a direct TCP connection carries
unsaved edits. NFS access alone is insufficient: the nodes must also be able to
connect to the chosen port.

On node A, open the source file and start a session:

```vim
:Peerpad
```

This also writes `.<name>.flash-share` beside the file with the host, port and
random token. When that file is opened in the active editor, ***FLASH*** asks whether to join; no
IP or token has to be exchanged. `:PeerpadJoin` without arguments joins the
current file's session, for example after declining or if the file was opened
before sharing started. The full manual command is also in `:messages`:

```vim
:PeerpadJoin <node-A-IP> <port> <token>
```

The sidecar is readable by the classes (owner/group/other) that may write the
source, so only people who can already change the file can join. It is removed
by `:PeerpadStop` or on exit. After a crash, it is cleaned up when someone on
the same host opens the file again; otherwise delete it by hand. Set
`vim.g.flash_share_discovery = false` before configuration loads to skip the per-open
check. During a session, set `require("peerpad").config.discovery = false` instead.

In Git repositories, discovery files and their temporary files are excluded through
local Git `info/exclude`, without changing the project's tracked settings. If safe
exclusion or sidecar creation fails, sharing continues through the manual command.
An already active advertised session still prevents a second owner. Background
previews do not prompt to join. If the target window or text changes during connection,
the shared buffer stays available through `:buffer` rather than replacing that editor.

Both users edit the newly opened shared buffer. Do not continue editing the
original NFS buffer independently. Concurrent insertions and overlapping
deletions are rebased rather than replacing the other user's buffer wholesale.

| Command / key | Action |
| --- | --- |
| `<leader>Ps` | Start sharing |
| `<leader>Pj` | Join the current file's session |
| `<leader>Pq` | Stop sharing |
| `<leader>Pi` | Show session status |
| `:Peerpad [port] [bind-address]` | Host the current source buffer and advertise it; defaults to a free port on `0.0.0.0` |
| `:PeerpadJoin [<host> <port> <token>]` | Join the current file's advertised session, or the given one |
| `:PeerpadStatus` | Show owner/guest, revision, pending edits and where each peer is |
| `u`, `Ctrl+r` | Undo/redo your own shared edits; each buffer change is one step |
| `:w` in the owner's shared buffer | Save synchronized text through the original source buffer |
| `:PeerpadStop` | Disconnect; on the owner, also stop the server |

Shared buffers are isolated `acwrite` buffers with their own in-memory undo
history. The original buffer and its persistent undo remain intact. Source-only
LSP, outline, formatting and project analysis do not attach to the shared buffer;
normal filetype syntax and native editing remain available. Use `u`/`Ctrl+r`, not
the ordinary undo browser or `:undo`, inside a shared buffer.

Only the owner saves. Guest writes, writes to other paths and appends are refused.
Saving is refused while the owner has pending edits, or if the original buffer or
disk contents changed outside the session. Disconnecting shows a notification.
If the shared text matches the loaded original and no edits are pending, its
windows return to the original without changing the split layout, and the redundant
shared buffer is removed. Otherwise a `[disconnected]` snapshot is retained;
copy its text into a normal buffer to recover unsaved work. The source is never
overwritten or reloaded during disconnect. Sessions do not automatically reconnect
or survive Neovim exit.

The module is loaded only when a share command is used or an opened file has a
sidecar; otherwise each file read costs one `stat`. There is no file polling or
idle timer, and cursor movement is sent only from shared buffers; one-shot timers only bound connection and
authentication (5 and 10 seconds). Editing reads changed buffer ranges; document
rebasing still has a cost. Documents are limited to 1 MiB and edit/history queues are bounded.
Sessions accept eight participants including the owner; set
`vim.g.flash_share_max_peers` (2-64) before `:Peerpad` to change it. Joining
a full session reports that instead of a reset connection. Multi-file workspace
sharing is not provided.

Each peer's cursor is highlighted in its own color with a `user@IP` label at the
end of that line. The IP is the address the owner's server observed, so it
cannot be forged by the peer; peers on the owner's host show the host's address.
The user name is reported by the peer itself; when two participants share a
label, the later one gets a `#<id>` suffix. Cursors are sent only when the
peer's edits are synchronized and follow later edits until the next update.
Override `LiveSharePeer1`..`LiveSharePeer6` to change the colors.

The final newline of the shared text is fixed: an edit that would remove it or
add text after it is sent as the equivalent edit before it, so concurrent edits
near the end of the file always merge into valid text. TCP transport
is token-authenticated but **not encrypted**: anyone who can observe the
network, or read the sidecar, can join and read the text. Peers' text cannot set
options through modelines. Use a trusted internal network or
an SSH tunnel, and do not expose the listener to the public Internet.

### Updating peerpad independently

`nvim/.config/nvim/lua/peerpad/` contains the same four modules as the
standalone `peerpad.nvim` repository. ***FLASH*** buffer eligibility
stays in `lua/peerpad/config.lua`. Common commands, shortcuts
and discovery are registered once by `peerpad.setup()`.
From the dotfiles checkout, copy only the modules after updating the sibling repository:

```sh
cp -R ../peerpad.nvim/lua/peerpad/. nvim/.config/nvim/lua/peerpad/
```

No plugin installation or changes to the rest of ***FLASH*** are required. Restart Neovim
after updating. ***FLASH*** and Package-based Neovim use the same `:Peerpad`, `:PeerpadJoin`,
`:PeerpadStop` and `:PeerpadStatus` commands.

## Configuration structure

The [entry point](../nvim/.config/nvim/init.lua) loads adjacent
[feature modules](../nvim/.config/nvim/lua/) in explicit dependency order.
It resolves symlinks and keeps the runtime isolated from Package-based Neovim modules/plugins.

| Owner | Responsibility |
| --- | --- |
| `options`, `keymaps`, `theme` | Runtime, settings, editing keys, appearance |
| `buffer_policy`, `bigfile` | Source/editor classification and analysis eligibility |
| `project`, `jobs`, `state` | Roots, cancellable work, shared interfaces/state |
| `explorer`, `navigation`, `buffers` | Tree, editor targets, buffer lifecycle |
| `pickers`, `search`, `editing` | Search UI, results, undo preview |
| `git`, `git_actions` | Status, signs, diff, blame, staging and hunk actions |
| `lsp/`, `tags`, `completion`, `format`, `diagnostics` | Language tools and editing assistance |
| `outline`, `breadcrumb_symbols`, `breadcrumbs`, `context` | Cached symbols, outline, context navigation |
| `dashboard`, `terminal`, `session` | Auxiliary UI and session lifecycle |
| `peerpad/` | Collaboration setup (`config.lua`), transport, rebasing and private undo |
| `statusline`, `indent`, `syntax`, `whichkey` | Native display and key guide |

LSP code lives in `lua/lsp/`: `servers.lua` lists commands and filetypes,
`init.lua` resolves tools and registers clients, `python.lua` owns interpreter
selection, `keymaps.lua` owns attached-buffer mappings, `lifecycle.lua` owns
restart/detachment and new-file recovery, and `diagnostics.lua` handles diagnostic
responses and catches up skipped hidden-buffer updates when shown again.
The top-level `lua/diagnostics.lua` owns diagnostic UI shortcuts.

Feature-private state stays local; shared interfaces live in `state.lua`, with
implementations owned by their feature. `buffer_policy.lua` distinguishes editable
source buffers from analysis-eligible buffers and auxiliary windows. Async work
checks eligibility before starting and applying results. `NopackBufferRestricted`
notifies features to cancel requests and clean up their UI; LSP detachment belongs
to `lsp/lifecycle.lua`, not the large-file detector. Project invalidation and process
cancellation belong to `project.lua` and `jobs.lua`. To investigate performance,
inspect the owning feature's events and callbacks, not just its file size.
