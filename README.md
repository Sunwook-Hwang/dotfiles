# Dotfiles

macOS-focused dotfiles for zsh, git, Herdr, tmux, Neovim, and Vim.

## Package-free Native Neovim

FLASH was built for servers with restricted network access and limited performance.
Bring just the Neovim configuration directory and start editing immediately,
without downloading plugins or parsers.

This repository includes [`nvim/init.lua`](nvim/.config/nvim/init.lua),
a **package-free Native Neovim configuration** for Neovim 0.12+.
It uses no plugin manager and no external Lua plugins, and it performs no plugin
or parser downloads. Built-in replacements provide a dashboard, fuzzy pickers,
a file tree, a leader-key guide, Sticky Scroll, Git signs and inline blame, LSP,
completion, formatting, sessions, an undo browser, and a reusable terminal.
Opt-in [single-buffer collaboration](https://github.com/Sunwook-Hwang/peerpad.nvim) uses
Neovim's native TCP APIs without a plugin or a separate server executable.

Optional language servers, formatters, and command-line search tools are used
only when already installed. See the feature guide in
[English](docs/flash.md) or
[한국어](docs/flash.ko.md).

For **Vim 9.0+**, [`vim/.vimrc`](vim/.vimrc) provides a standalone, plugin-free
Vimscript counterpart with the same core shortcuts. It uses **ctags instead of
LSP**, with native commenting, completion, pickers, netrw, Git, formatting,
dashboard, Sticky Scroll, sessions, and undo previews. No Lua support is needed.
See the Vim guide in [English](docs/vim-nopack-features.md) or
[한국어](docs/vim-nopack-features.ko.md).

## Performance by use case

FLASH, pvi and vimrc serve different workflows, so there is no overall winner.
The studies contain 91 runs across two use cases:

- **FLASH and vimrc:** vimrc does not support LSP, so FLASH's LSP was disabled
  and both profiles used their actual ctags-based `gd` mappings in the same
  project. This matches the supported navigation level for this specific task;
  it does not make every editor feature equivalent.
- **FLASH and pvi:** both support LSP, so the added comparison uses the same ty
  0.0.84 executable, Python 3.14.8, project, client capabilities, settings and
  change debounce. Actual profile attachment hooks, UI and `gd` mappings remain.
  This matches the tested LSP tasks, not all supported features or languages.

Matched ty LSP results (seven runs per profile; 14 runs total):

| Measurement                            |      FLASH |        pvi | FLASH change vs pvi |
| -------------------------------------- | ---------: | ---------: | ------------------: |
| Actual mapped gd after warmup          |    1.00 ms |    7.04 ms |              -85.8% |
| Completion response, excluding popup   |    4.17 ms |    4.42 ms |               -5.7% |
| Saved edit → undefined-name diagnostic |    9.03 ms |   10.82 ms |              -16.5% |
| Saved correction → diagnostic cleared  |    8.63 ms |    8.85 ms |               -2.5% |
| Editor + ty RSS snapshot               | 107.70 MiB | 118.39 MiB |               -9.0% |

All 294 mapped definition jumps and 70 diagnostic error/clear cycles passed without
restarting ty. Direct definition requests were close (0.14 ms vs 0.15 ms), so mapped
gd differences include each profile's dispatch/UI path. Memory is a single RSS
snapshot after diagnostic cycles, not a peak or unique physical-memory total.
See the matched LSP report in [English](docs/performance/flash-pvi-lsp.md) or
[한국어](docs/performance/flash-pvi-lsp.ko.md).

Separate LSP-disabled editing baseline: 2,000-line results (seven-run medians):

| Measurement                     |    FLASH |      pvi | FLASH change vs pvi |
| ------------------------------- | -------: | -------: | ------------------: |
| Peak editor memory              | 18.4 MiB | 24.2 MiB |              −24.0% |
| 600 cursor moves with redraw    |   472 ms |   600 ms |              −21.4% |
| 200 window switches with redraw |   271 ms |   309 ms |              −12.3% |

| Ctags task                                  |    FLASH |    vimrc | FLASH change vs vimrc |
| ------------------------------------------- | -------: | -------: | --------------------: |
| First definition lookup, including indexing | 60.76 ms | 74.43 ms |                −18.4% |
| Indexed definition lookup                   |  1.71 ms |  2.54 ms |                −32.6% |

Percent change is `(result / baseline − 1) × 100`; negative values mean less
memory or elapsed time, not an overall speed improvement. The indexed ctags
lookup difference is only 0.83 ms.

Measurements used a Mac mini M4, not a restricted Linux server. Peak memory
excludes child processes, while the added LSP study also reports ty RSS separately.
Large-file results are reported separately because protective policies reduce
functionality. SSH/NFS, weak-server LSP workloads and complete feature parity
have not been measured.

See the use-case comparison in [English](docs/performance/flash-pvi-vimrc.md) or
[한국어](docs/performance/flash-pvi-vimrc.ko.md), and the
[performance index](docs/performance/README.md) for ctags results, methodology,
raw data, and historical experiments.

## Setup

macOS:

```sh
git clone --depth 1 https://github.com/Sunwook-Hwang/dotfiles.git ~/dotfiles
cd ~/dotfiles
./mac_setup.sh
```

Linux:

```sh
git clone --depth 1 https://github.com/Sunwook-Hwang/dotfiles.git ~/dotfiles
cd ~/dotfiles
./linux_setup.sh
```

Run the complete first-time macOS setup (equivalent to `./mac_setup.sh`):

```sh
./mac_setup.sh base
```

Update Homebrew itself:

```sh
./mac_setup.sh brew
```

Install only Linux packages:

```sh
./linux_setup.sh base
```

Link or unlink dotfiles on either platform:

```sh
./mac_setup.sh link
./mac_setup.sh unlink
./linux_setup.sh link
./linux_setup.sh unlink
```

## Included

- `zsh`: oh-my-zsh config and shell aliases
- `csh`: C shell/tcsh command aliases, PATH, and native tcsh history/completion
- `tools`: shared editor launcher and `dotformat` command
- `claude`: global Claude Code guidance
- `codex`: global Codex guidance
- `git`: git defaults
- `herdr`: terminal multiplexer keybindings
- `tmux`: tmux keybindings and theme
- `nvim-pack`: pack Neovim config
- `nvim`: FLASH, the default modular, package-free Neovim config
- `neovide-terminal`: standalone Neovide terminal config
- `vim`: single-file nopack Vim 9.0+ config (`~/.vimrc`)

## Git identity

Set your name and email in a local file that is not part of this repository:

```bash
git config --file ~/.gitconfig.local user.name "Your Name"
git config --file ~/.gitconfig.local user.email "you@example.com"
```

The shared `.gitconfig` includes this optional file. Use it for personal Git
settings instead of adding them to the shared configuration.

## Nopack Neovim

For restricted servers, use [`nvim/init.lua`](nvim/.config/nvim/init.lua).
It requires **Neovim 0.12+** and uses feature modules under its own `lua/` directory with
Neovim's bundled runtime and existing system tools. It does not download
plugins, parsers, language servers, or formatters.

With the Stow setup:

```sh
NVIM_APPNAME=nvim nvim
```

On a server, copy `init.lua` and its adjacent `lua/` directory together, then run:

```sh
nvim -u /path/to/init.lua
```

Pack configuration is installed at `~/.config/nvim-pack/init.lua`, with feature
modules in its adjacent `lua/` directory. FLASH is the default configuration at
`~/.config/nvim/`, with its own `init.lua` and `lua/` directory.
See [FLASH configuration structure](docs/flash.md#configuration-structure) for module responsibilities.

`vi` always starts FLASH in `~/.config/nvim/`. `pvi` explicitly starts the
package profile in `~/.config/nvim-pack/` with `NVIM_APPNAME=nvim-pack`.
There is no remembered mode, selector file, or launcher script.

```sh
vi                       # FLASH / no packages
pvi                      # package profile
nvim                     # FLASH (default Neovim configuration)
```

Zsh and C shell use the same two aliases. Reload the relevant shell configuration
after installing: `source ~/.zshrc` or `source ~/.cshrc`.
The installer preserves existing package downloads and Mason tools under
`~/.local/share/nvim-pack/`. FLASH can reuse those Mason tools without loading
plugins. Undo and sessions stay shared under `~/.local/state/nvim/`.

Neovide uses a separate terminal profile at `~/.config/neovide-terminal/init.lua`:

```sh
NVIM_APPNAME=neovide-terminal neovide
```

On macOS, `./mac_setup.sh` and `./mac_setup.sh base` install Neovide and configure its app icon to open
this terminal profile automatically. You can also set up just this integration
with `./mac_setup.sh neovide`. The app is available at
`~/Applications/Neovide.app` and is automatically added to the Dock using `dockutil`.
Running setup again restores a removed Dock icon or replaces the existing Neovide entry.

The `neovide` shell alias selects this profile. The shell inside Neovide does not
inherit that profile, so nested Neovim can use pack or nopack independently.

When copying pack configuration to another machine, include the adjacent
`lua/` directory. See [Pack configuration structure](docs/nvim-pack-structure.md).

When an update adds or renames configuration files, `git pull` alone does not
create new file-level Stow links. From the repository, run:

```sh
git pull --ff-only
./clean_dotfiles.sh
./install_dotfiles.sh
```

The installer verifies both named configuration links and the launcher. Existing
conflicting files are backed up before installation. Mode selection survives
clean/reinstall; a fresh install defaults to nopack.

| Feature         | Nopack behavior                                                                                                                 |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| Completion      | Native LSP completion on server-defined triggers; buffer words and ctags fallback without LSP                                   |
| Completion keys | `Ctrl-Space` requests candidates, `Ctrl-n/p` selects, `Enter` accepts; `Tab` / `Shift-Tab` navigates snippets or candidates     |
| Definition      | `gd` uses LSP first, then saved-file ctags definitions                                                                          |
| LSP             | Native client; `<leader>ls` restarts current-buffer clients, `<leader>lv` selects the Python environment                            |
| Formatting      | `<leader>lf` runs installed formatters asynchronously or falls back to LSP; no format-on-save                                     |
| Search          | `<leader>f` finds files, `<leader><CR>` finds Git-tracked files, `<leader>st` searches text live, `<leader>t` searches the cursor word |
| Code outline    | `<leader>o` opens LSP symbols or a ctags fallback; `Enter` jumps, `r` refreshes, `q` closes                                       |
| File tree       | `<leader>e` opens an editable project-root tree and reveals the current file; indentation guides, Git signs, hidden/ignored toggles, and nested path creation |
| Git             | Unstaged line signs, branch/file status, and side-by-side index/HEAD diff with `<leader>gd/gD`                                    |
| Terminal        | `Ctrl-t` toggles a reusable bottom split; `Esc Esc` exits Terminal mode                                                         |
| Auto pairs      | Brackets `() [] {}`, single/double quotes, and backticks; skip existing closers and delete empty pairs                          |
| Undo            | `<leader>u` previews saved undo states before applying one                                                                        |
| Highlighting    | Bundled Treesitter parsers when available, otherwise syntax highlighting; native indent guides                                  |

LSP and formatter launchers are searched on `PATH` first, then in an existing `stdpath("data")/mason/bin` directory without loading
Mason or installing tools. Auxiliary servers require project configuration or
dependencies. Ctags fallback supports C/C++ and Python using Universal or
Exuberant Ctags. Search uses installed `find`, `git`, and `rg` or `grep`.

Large files disable expensive editing features. Ctags cache merging runs in a
worker thread, and Git/tree/tabline caches avoid repeated work during editing.
The built-in picker and outline provide a smaller feature set than Telescope
and Aerial; a native leader-key guide replaces Which-key, while DAP is not included.

See the FLASH guide in [English](docs/flash.md) or [한국어](docs/flash.ko.md)
for features, keymaps, tool setup, server transfer, ctags, and configuration structure.

## Formatting

Project formatter configuration is stored in the repository and used by pvi,
vi, and Vim. See [Formatting rules](docs/formatting.md) for per-language settings
and reuse in other projects.

After installation, use `dotformat <format> [project-path]` to copy the rules:

```sh
dotformat lua                 # Current directory
dotformat python ~/my-project
dotformat prettier ~/web-project
dotformat shell
```

Existing files are preserved. The command copies configuration only; it does not
format source files. It is installed at `~/.local/bin/dotformat`, already on PATH
in the provided Zsh configuration.
