# VS Code

Shared settings, FLASH-style Vim keybindings, snippets and extension IDs for
macOS and Linux. Requires VS Code; extensions are downloaded from its Marketplace.

```sh
./install_dotfiles.sh  # Stow settings and install missing extensions
./clean_dotfiles.sh    # Unstow settings; keep extensions
```

Both commands run from this repository and use Bash. Do not source them.
There is no separate VS Code installer.

## Installation and backups

`vscode/user/` is a GNU Stow package containing `settings.json`,
`keybindings.json` and `snippets/`. The main installer selects the **Default
profile** directory as its Stow target:

- macOS: `~/Library/Application Support/Code/User/`
- Linux: `${XDG_CONFIG_HOME:-~/.config}/Code/User/`

Existing conflicting files or links are moved under the main installer's
`~/.dotfiles-backup/<timestamp>/vscode/` directory before linking. Already-correct
links are kept without another backup. The log reports the linked destination.
The clean command removes Stow-owned links without restoring backups or
uninstalling extensions.

Changes made through VS Code or Settings Sync reach the linked repository files.
Review `git diff -- vscode/` before committing. The
`settingsSync.keybindingsPerPlatform` setting is disabled so the same user
keybindings sync across macOS, Windows and Linux. Resolve Sync conflicts before
accepting cloud or local replacements. Keep the checkout in place while linked.

The installer finds `code` on PATH, with a fallback to standard macOS app
locations. It queries installed extension IDs once and installs only missing
extensions from `vscode/extensions.txt`. Existing extensions keep VS Code's normal
automatic update behavior. A missing CLI leaves settings linked and prints an
instruction to rerun after installing VS Code. Extension installation failures
are reported and cause a nonzero exit after processing the list.

## Other profiles and installations

The default installation does not modify existing named profiles. Select
**Default** in VS Code to use these settings. No machine-specific profile ID is
stored here.

`VSCODE_USER_DIR` overrides the settings target directory. It does not select
an extension profile, so use the normal Default-profile target when running the
main installer. `CODE_BIN` selects the VS Code CLI executable.
`STOW_BACKUP_DIR` overrides the main installer's backup directory.

## Included behavior

- `jk` leaves Insert mode; `H` / `L` switch editor tabs in Normal mode.
- `n` / `N` search, open folds and center the result.
- `Ctrl+h/j/k/l` navigate panes. Completion and Quick Open keep their own
  `Ctrl+j/k` and `Ctrl+n/p` navigation.
- Visual `p` / `P` preserve the copied register; `<` / `>` keep the selection.
- Visual `*` / `#` search the selected text using VSCodeVim's normal behavior.
  They advance to another match; FLASH's search-without-moving behavior is not
  implemented here.
- Space opens which-key in Normal and Visual modes. `<leader>gl` toggles line
  blame, which is off by default.
- Automatic completion popups are disabled, matching the exported local profile;
  manually triggered completion still uses the navigation bindings above.

The extension list follows the source profile's public extensions and adds
Bookmarks for the existing bookmark shortcuts. The internal audio integration
is excluded. Extensions and their versions are managed by VS Code, not vendored
into this repository.

## Extension synchronization and export

Settings Sync is enabled through VS Code's account menu, not by a `settings.json`
switch. Sign in on each machine and select Settings, Keyboard Shortcuts, Snippets
and Extensions under **Settings Sync: Configure**. The repository sets
`settingsSync.keybindingsPerPlatform` to `false` for shared keyboard shortcuts.

Use VS Code's built-in Settings Sync with **Extensions** enabled to synchronize
installed extensions between computers. The dotfiles do not run a background
watcher or automatically rewrite `extensions.txt`.

To update installed packages and extensions and refresh the list, run:

```sh
./mac_setup.sh update    # macOS
./linux_setup.sh update  # Linux
```

The update target upgrades packages through Homebrew or the Linux distribution's
package manager, updates installed VS Code extensions, exports their current list,
then reapplies the Stow links. Export runs before extension installation so an
extension removed in VS Code is not restored from an old manifest. Missing VS Code
is skipped without modifying the list. Package or CLI failures stop the update.
Tools installed outside these package managers are not upgraded by this target.
The command does not fetch or merge Git changes.

To export only, without package or extension updates, use
`./vscode/export_extensions.sh`.

This exports the Default profile's installed extension IDs, including disabled
extensions, as a sorted list. It excludes the internal `openai.codex-audio`
integration and does not export installation paths or credentials. Review the
list for any other private extensions before publishing. `CODE_BIN` selects a
specific VS Code CLI. Named profiles and remote SSH/WSL extensions are not
included in this Default-profile snapshot.

A failed CLI query or invalid output preserves the existing file. Review
`git diff -- vscode/extensions.txt`, then commit when ready. Export alone does not
install, uninstall, commit or push anything. `install_dotfiles.sh` continues to
install missing extensions from the saved list without changing it.

## Private data

Only settings, keybindings, snippets and public extension IDs are included.
Accounts, credentials, cloud project IDs, local paths, profile IDs, caches and
runtime databases are excluded. Automatic workspace/notebook trust overrides
are also omitted. Keep machine-specific settings and credentials outside this
repository. Do not add them to a linked settings file unless they are safe to
publish.
