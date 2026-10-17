# VS Code

Shared settings, FLASH-style Vim keybindings, snippets and extension IDs for
macOS and Linux. Requires VS Code; extensions are downloaded from its Marketplace.

```sh
./vscode/install.sh                    # Link settings and install extensions
./vscode/install.sh --skip-extensions  # Link settings only
./vscode/install.sh --unlink           # Remove this checkout's links
```

Run the script from any working directory by specifying its path. It uses
`/bin/sh`, so it can also be launched from Zsh, Bash or C shell as an executable.
Do not source it.

`install_dotfiles.sh` links the settings and installs the listed extensions;
`clean_dotfiles.sh` removes the links. Extensions are never uninstalled.

## Installation and backups

The installer targets the **Default profile**:

- macOS: `~/Library/Application Support/Code/User/`
- Linux: `${XDG_CONFIG_HOME:-~/.config}/Code/User/`

It backs up existing `settings.json`, `keybindings.json` and the entire
`snippets/` directory under `~/.dotfiles-backup/vscode-<timestamp>.<suffix>/`
before replacing them with links into this checkout. Each backup directory is
unique. Reinstalling already-correct links does not create another backup.
Unlinking removes only links owned by this checkout and does not restore backups
automatically. Restore saved files after unlinking if needed.

Changes made through VS Code's Settings editor or keyboard shortcuts editor
also change the linked repository files, so `git diff -- vscode/` shows them.
The checkout must remain in place; rerun installation if it moves.

The installer finds `code` on PATH, with a fallback to the standard macOS app
locations. If it cannot find the CLI, it links the configuration and prints how
to finish extension installation. Individual extension failures are reported,
and the installer exits with a nonzero status after processing the list.

## Other profiles and installations

Existing named profiles are not modified by the default installation. Select
**Default** in VS Code to use these settings. No machine-specific profile ID is
stored in this repository.

For a different configuration directory, set `VSCODE_USER_DIR`. When targeting a
named profile's directory, link settings only and install its extensions with
the matching profile name:

```sh
VSCODE_USER_DIR="/path/to/Code/User/profiles/your-profile-id" \
  ./vscode/install.sh --skip-extensions

while IFS= read -r extension; do
  code --profile "Your Profile" --install-extension "$extension"
done < vscode/extensions.txt
```

`CODE_BIN` can select another CLI executable; `VSCODE_BACKUP_ROOT` can select
another backup parent directory.

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

## Private data

Only settings, keybindings, snippets and public extension IDs are included.
Accounts, credentials, cloud project IDs, local paths, profile IDs, caches and
runtime databases are excluded. Automatic workspace/notebook trust overrides
are also omitted. Keep machine-specific settings and credentials outside this
repository. Do not add them to a linked settings file unless they are safe to
publish.
