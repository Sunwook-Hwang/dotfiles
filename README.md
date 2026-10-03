# Dotfiles

Personal dotfiles for a consistent shell, terminal and editing environment across
macOS and Linux. This repository manages zsh and C shell/tcsh, Git, Ghostty,
Neovide, Herdr, tmux, Neovim and Vim configurations, together with setup scripts
and project formatting rules. GNU Stow links the configurations from this
checkout into the home directory.

Particular attention goes to Neovim: ***FLASH*** provides a package-free native
configuration for servers with restricted network access and limited resources.
See [Usage](#usage) for launch commands and server transfer.
A Package-based Neovim configuration offers a similar workflow with plugins,
and Plugin-free Vim provides a ctags-based alternative for Vim 9.0+.

## Included

- `zsh`: oh-my-zsh config and shell aliases
- `csh`: C shell/tcsh command aliases, PATH, and native tcsh history/completion
- `tools`: shared editor launcher and `dotformat` command
- `claude`: global Claude Code guidance
- `codex`: global Codex guidance
- `git`: git defaults
- `ghostty`: terminal configuration and fonts
- `herdr`: terminal multiplexer keybindings
- `tmux`: tmux keybindings and theme
- `nvim-pack`: package-based Neovim config matching ***FLASH***'s core workflow; launched with `pvi`
- `nvim`: ***FLASH***, the default modular, package-free Neovim config
- `neovide-terminal`: standalone Neovide terminal config
- `vim`: plugin-free Vim 9.0+ configuration matching ***FLASH***'s core workflow, using ctags instead of LSP (`~/.vimrc`)

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

## (Neo)Vim configurations

### ***FLASH*** : Package-free Native Neovim · [English](docs/flash.md) / [한국어](docs/flash.ko.md)

***FLASH*** was built for servers with restricted network access and limited performance.
Bring just the Neovim configuration directory and start editing immediately,
without downloading plugins or parsers.

This repository includes [`init.lua`](nvim/.config/nvim/init.lua),
a **package-free Native Neovim configuration** for Neovim 0.12+.
It uses no plugin manager and no external Lua plugins, and it performs no plugin
or parser downloads. Built-in replacements provide a dashboard, fuzzy pickers,
a file tree, a leader-key guide, Sticky Scroll, Git signs and inline blame, LSP,
completion, formatting, sessions, an undo browser, and a reusable terminal.
Opt-in [single-buffer collaboration](https://github.com/Sunwook-Hwang/peerpad.nvim) uses
Neovim's native TCP APIs without a plugin or a separate server executable.

Optional language servers, formatters, and command-line search tools are used
only when already installed.

### Package-based Neovim · [English](docs/package-based-neovim.md) / [한국어](docs/package-based-neovim.ko.md)

This repository also provides a **package-based Neovim configuration**, launched
with the `pvi` command. **`pvi` is only the launcher command**, not a separate
editor or plugin. Its configuration lives in `~/.config/nvim-pack/` and uses
Neovim's built-in `vim.pack` manager to load external plugins.

The package profile is built to closely match ***FLASH***'s core features, shortcuts
and editing workflow, using plugins where useful alongside native implementations.
Both offer LSP, completion, formatting, file navigation, Git tools, sessions and
terminals, though individual interfaces and behavior can differ. Choose ***FLASH***
for a configuration without external Lua plugins, or the package profile for
plugin-backed features.

### Plugin-free Vim · [English](docs/plugin-free-vim.md) / [한국어](docs/plugin-free-vim.ko.md)

For **Vim 9.0+**, this repository provides a **plugin-free Vim configuration**
in [`vim/.vimrc`](vim/.vimrc), installed as `~/.vimrc`. **vimrc is the configuration
file, not an editor or launcher command.** Open Vim with `vim` to use it; this
repository's `vi` alias launches ***FLASH*** in Neovim instead.

The Vim configuration is written in Vimscript and built to match ***FLASH***'s core
shortcuts and editing workflow as closely as Vim permits. It provides native
commenting, completion, pickers, a file tree, Git tools, formatting, a dashboard,
Sticky Scroll, sessions, undo previews and terminals without Lua or plugins.
It uses **ctags instead of LSP**, so language-server features are not equivalent
to ***FLASH*** or the package-based Neovim profile. Individual interfaces can also differ.

## Built for constrained servers: how ***FLASH*** avoids repeated work

***FLASH*** targets servers where network access is restricted and CPU or memory is
limited. In that environment, repeated scans, overlapping subprocesses and queued
obsolete work can interrupt editing. ***FLASH*** uses Neovim's built-in APIs without
an external Lua plugin stack and applies the following algorithms to limit
that work:

- **Event-driven cache invalidation.** The
  [statusline](nvim/.config/nvim/lua/statusline.lua) keeps diagnostic counts and
  attached-client information, invalidating them on diagnostic or LSP events.
  Redrawing the statusline does not repeatedly scan all workspace clients;
  unchanged information is reused instead of recomputed for every cursor move.
- **Input-aware caching and a latest-only pending job.** [Git signs](nvim/.config/nvim/lua/git.lua) reuse
  base-file data while the Git index stamp is unchanged and keep only the latest
  pending diff when a diff job is already running. Rapid edits replace that
  pending snapshot instead of growing a queue of obsolete diffs.
- **Request deduplication and cancellation.** The
  [definition handler](nvim/.config/nvim/lua/tags.lua) shares an outstanding `gd`
  request at an unchanged cursor position and cancels obsolete requests. A
  single resolved target opens directly; multiple targets use a native picker.
  Late responses are checked against the original buffer, edit version and cursor
  position before they can move the editor.
- **Batched, incremental ctags indexing.** The same
  [tags module](nvim/.config/nvim/lua/tags.lua) reuses project indexes, groups
  pending files in a set and runs one indexing batch per project at a time.
  File updates can be indexed without rebuilding the whole project; a full
  project build is available when needed. Repeated file requests do not duplicate
  entries in the pending batch.
- **Changed-range checks and explicit large-file limits.**
  [Large-file detection](nvim/.config/nvim/lua/bigfile.lua) merges changed ranges
  and defers inspection outside buffer text locks. Normal edits check the
  affected ranges instead of rescanning every line. Files over 2 MiB, 50,000
  lines, or 10,000 bytes in one line enter a protective mode that reduces
  expensive features. Those benchmarks are reported separately because less
  functionality remains active.
- **Shared eligibility and stale-result checks.** The
  [shared policy](nvim/.config/nvim/lua/buffer_policy.lua) limits automatic analysis
  to eligible source buffers. Background results can be checked against the
  original file, filetype and buffer change counter, so obsolete results do not
  overwrite newer source state.

These are verified implementation choices, not individually measured speedups.
The matched ty experiment found similar direct definition-request times, but a
shorter mapped `gd` path and lower editor RSS for ***FLASH***. It does not isolate a
specific plugin as the cause. ty's memory use was similar in both profiles, so
the total editor-plus-server memory difference was smaller than the editor-only
difference. No claim is made that removing plugins always makes an editor faster.

## Performance by use case

***FLASH***, Package-based Neovim (launched with `pvi`), and Plugin-free Vim have different
implementations and feature sets, so there is no overall winner.
The studies contain 91 runs across two use cases:

- ***FLASH* and Plugin-free Vim:** the Vim configuration does not support LSP, so ***FLASH***'s LSP was disabled
  and both profiles used their actual ctags-based `gd` mappings in the same
  project. This matches the supported navigation level for this specific task;
  it does not make every editor feature equivalent.
- ***FLASH* and Package-based Neovim:** both support LSP, so the added comparison uses the same ty
  0.0.84 executable, Python 3.14.8, project, client capabilities, settings and
  change debounce. Actual profile attachment hooks, UI and `gd` mappings remain.
  This matches the tested LSP tasks, not all supported features or languages.

Matched ty LSP results (seven runs per profile; 14 runs total):

| Measurement                            |      ***FLASH*** | Package-based Neovim | ***FLASH*** change vs Package-based Neovim |
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
See the matched LSP report in [English](docs/performance/flash-package-based-neovim-lsp.md) or
[한국어](docs/performance/flash-package-based-neovim-lsp.ko.md).

Separate LSP-disabled editing baseline: 2,000-line results (seven-run medians):

| Measurement                     |    ***FLASH*** | Package-based Neovim | ***FLASH*** change vs Package-based Neovim |
| ------------------------------- | -------: | -------: | ------------------: |
| Peak editor memory              | 18.4 MiB | 24.2 MiB |              −24.0% |
| 600 cursor moves with redraw    |   472 ms |   600 ms |              −21.4% |
| 200 window switches with redraw |   271 ms |   309 ms |              −12.3% |

| Ctags task                                  |    ***FLASH*** | Plugin-free Vim | ***FLASH*** change vs Plugin-free Vim |
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

See the use-case comparison in [English](docs/performance/editor-baseline.md) or
[한국어](docs/performance/editor-baseline.ko.md), and the
[performance index](docs/performance/README.md) for ctags results, methodology,
raw data, and historical experiments.

## Git identity

Set your name and email in a local file that is not part of this repository:

```bash
git config --file ~/.gitconfig.local user.name "Your Name"
git config --file ~/.gitconfig.local user.email "you@example.com"
```

The shared `.gitconfig` includes this optional file. Use it for personal Git
settings instead of adding them to the shared configuration.

## Usage

After the dotfiles installation, use:

```sh
vi        # FLASH, the default Neovim configuration (also available as nvim)
pvi       # Package-based Neovim
vim       # Plugin-free Vim
neovide   # Neovide terminal profile
```

Reload your shell configuration to use the aliases: `source ~/.zshrc` or
`source ~/.cshrc`. On macOS, the setup also configures the Neovide Dock icon.

For a restricted server with **Neovim 0.12+**, copy `init.lua` and its adjacent
`lua/` directory from `nvim/.config/nvim/` into `~/.config/nvim/`, then run `nvim`.

After pulling updates that add or rename configuration files, rerun
`./install_dotfiles.sh` from the checkout to refresh the Stow links.

## Formatting

Project formatter configuration is stored in the repository and used by ***FLASH***,
the package profile, and the Vim configuration. See [Formatting rules](docs/formatting.md) for per-language settings
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
