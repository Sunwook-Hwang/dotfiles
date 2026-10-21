# Dotfiles

Personal dotfiles for a consistent shell, terminal and editing environment on
macOS and Linux. GNU Stow links the configurations from this checkout into the
home directory; VS Code settings are copied instead.

The editor configuration is ***FLASH***: package-free native Neovim for servers
with restricted network access and limited resources.

## Included

- `nvim`: ***FLASH***, the modular, package-free Neovim configuration.
- `neovide-terminal`: Neovide is a Neovim GUI, configured here as a **standalone
  terminal**. It opens directly in a shell, hides editor UI, and provides font
  zoom and clipboard paste shortcuts. macOS setup also configures its Dock icon.
- `zsh`, `csh`: Zsh and C shell/tcsh settings, aliases and local overrides.
- `git`: shared Git defaults with an optional private identity file.
- `ghostty`, `herdr`, `tmux`: terminal and multiplexer settings.
- `claude`, `codex`: coding-agent guidance.
- `tools`: the `dotformat` command and shared project formatting rules.
- `vscode`: VS Code settings with an interface and editing workflow aligned as
  closely as possible with ***FLASH***. See the [VS Code setup](vscode/README.md).

## Setup

```sh
git clone --depth 1 https://github.com/Sunwook-Hwang/dotfiles.git ~/dotfiles
cd ~/dotfiles
```

**The VS Code configuration assumes familiarity with Vim. If you are not
comfortable with Vim, do not use it.**

All configurations are included by default. To leave VS Code settings and
extensions untouched, add `--exclude vscode`:

```sh
./install_dotfiles.sh --exclude vscode
./mac_setup.sh base --exclude vscode
./linux_setup.sh --exclude vscode
./mac_setup.sh update --exclude vscode
```

The option also works with `link`, `unlink` and `clean_dotfiles.sh`. Existing
VS Code links are kept when excluded; settings, extensions and macOS VS Code
keyboard preferences are skipped. Other dotfiles are processed normally.

For the full setup, including VS Code:

```sh
./mac_setup.sh       # macOS
# or
./linux_setup.sh     # Linux
```

Both setup scripts expose only these targets:

| Target | macOS | Linux |
| --- | --- | --- |
| No argument | Full setup, same as `base` | Full setup, link dotfiles, then start Zsh |
| `base` | Full setup: packages, apps, fonts, shell, Neovide and dotfiles | Packages and Neovim only |
| `update` | Update Homebrew packages and VS Code extensions, export extensions, relink dotfiles | Update distribution packages and VS Code extensions, export extensions, relink dotfiles |
| `link` | Link dotfiles and install missing VS Code extensions | Same |
| `unlink` | Remove dotfiles links; keep installed programs and extensions | Same |

Other setup functions are internal steps, not command-line targets.

Setup includes `fzf` and language tools available from Homebrew or the Linux
package repositories. Unavailable Linux packages are skipped; no Mason installer
or additional package manager is downloaded.

To update installed packages and VS Code extensions, save the current extension
list and relink the dotfiles:

```sh
./mac_setup.sh update    # macOS
./linux_setup.sh update  # Linux distribution packages
```

Settings Sync must be enabled after signing in to VS Code on each machine; it
cannot be turned on through `settings.json` alone.

For linking or unlinking configurations without installing system packages:

```sh
./install_dotfiles.sh
./clean_dotfiles.sh
```

Existing conflicting files are moved into `~/.backup_dotfiles/` before linking.
Rerun the installer after updates that add or rename configuration files.

VS Code settings are backed up and copied to its **Default profile** on macOS and Linux,
and the listed extensions are installed when the VS Code CLI is available.

## ***FLASH*** : Package-free Native Neovim · [English](docs/flash.md) / [한국어](docs/flash.ko.md)

Bring `nvim/.config/nvim/` to a server with **Neovim 0.12+** and start editing.
No plugin manager, external Lua plugins, parser installation or startup downloads
are required. Language servers, formatters and search tools are optional external
executables and are used only when installed.

Native features include a dashboard, fuzzy file and text search, an editable file
tree, a leader-key guide, Git signs and blame, LSP and completion, formatting,
outline, Sticky Scroll, sessions, undo previews and a reusable terminal.
Optional collaboration uses the bundled [peerpad.nvim](https://github.com/Sunwook-Hwang/peerpad.nvim)
modules and Neovim's TCP APIs.

Bundled themes are adapted static color definitions. Their original repositories,
revisions, licenses and adaptation details are listed in the
[theme sources](nvim/.config/nvim/lua/themes/README.md).

## Usage

After installation, reload your shell with `source ~/.zshrc` or `source ~/.cshrc`:

```sh
vi        # FLASH; nvim also works
neovide   # Standalone terminal profile
```

To replace only the FLASH configuration from a release ZIP:

```sh
sh ./update_flash.sh /path/to/dotfiles-release.zip
```

Omit the ZIP argument to download the latest release. Existing configuration is
backed up; installed tools, sessions and undo data are preserved. See the
[update guide](docs/flash.md#update-from-a-release) for details.

## Local Git identity

```sh
git config --file ~/.gitconfig.local user.name "Your Name"
git config --file ~/.gitconfig.local user.email "you@example.com"
```

The shared Git configuration includes this optional local file.

## Project formatting

Use `dotformat <format> [project-path]` to copy project formatting rules. Existing
files are preserved; no formatter is run or installed.

```sh
dotformat lua
dotformat python ~/my-project
dotformat prettier ~/web-project
dotformat shell
```

See [Formatting rules](docs/formatting.md) for supported tools and configuration.

Earlier repository layouts remain available in [v0.1.8](https://github.com/Sunwook-Hwang/dotfiles/tree/v0.1.8).

## License

Original code and documentation are licensed under the [MIT License](LICENSE),
copyright (c) 2026 Sunwook Hwang. Third-party material retains its original
licenses; see the [theme source and license notices](nvim/.config/nvim/lua/themes/README.md).
