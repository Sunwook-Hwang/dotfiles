# VS Code

Shared settings, FLASH-style Vim keybindings, snippets and extension IDs for
macOS and Linux. Requires VS Code; extensions are downloaded from its Marketplace.

The VS Code interface, keybindings and editing workflow are aligned as closely
as possible with [***FLASH***](../docs/flash.md).
This configuration assumes familiarity with Vim. If you are not comfortable
with Vim editing and keybindings, do not use this VS Code configuration.

All configurations are included by default. Use `--exclude vscode` with
`install_dotfiles.sh`, `clean_dotfiles.sh`, `mac_setup.sh` or `linux_setup.sh`
to leave VS Code settings and extensions untouched (for example,
`./mac_setup.sh link --exclude vscode`). Existing VS Code links are not removed.

```sh
./install_dotfiles.sh  # Stow settings and install missing extensions
./clean_dotfiles.sh    # Unstow settings; keep extensions
```

Both commands run from this repository and use Bash. Do not source them.
There is no separate VS Code installer.

## Pane navigation

`Ctrl+h/j/k/l` moves between panes. Codex and Claude Code sidebar webviews have
an explicit fallback: `Ctrl+h` returns to the editor from the right sidebar,
and `Ctrl+l` returns from the left sidebar. This follows the configured sidebar
position. Webviews opened as editor tabs retain the normal directional bindings.
Native inputs, lists, terminals and Quick Open keep their existing bindings.
`Ctrl+;` returns to the active editor group from any view, opening an untitled
buffer if the group is empty, read-only, or displays a non-text page such as extension details.
Existing editable text and diff editors are kept. Space remains the leader key in Vim editing modes.
`Ctrl+Shift+1/2/3` toggles Codex, Claude Code, and Roo Code; `Ctrl+Shift+0` toggles Chat Sessions. These views use the right sidebar.

`<leader>o` opens Outline in its saved location and closes the secondary sidebar
when Outline is visible. Keep Outline in the right secondary sidebar for this
toggle; the supplied profile includes that placement.

## Transfer to another computer (including Windows)

Open **File → Preferences → Profiles** (macOS: **Code → Settings → Profiles**).
Use the dropdown next to **New Profile → Import Profile…**, select
`vscode/FLASH.code-profile`, then create/select the **FLASH** profile. To replace
the existing Default profile instead, enter its name in the import form and
confirm **Replace**. Export the existing profile first if you need a backup.
The file includes settings, keybindings,
snippets, extension IDs, view placement/visibility and status bar item visibility.
No Python or database editing is required on the destination computer.

Profiles are snapshots. To save subsequent changes, use **Profiles: Export Profile**
and save a local `.code-profile` file in this directory. Review it before sharing:
native exports can include additional extension state. The supplied profile excludes
accounts, credentials, local paths and history. Project-specific state (including
Outline follow-cursor preferences and open editor layouts) is not part of this transfer.

`python3 vscode/export_profile.py` rebuilds the supplied snapshot from this
repository's settings, keybindings, snippets and extension list, plus portable UI
preferences from the local Default profile. It only reads the VS Code database.
The Stow installer continues to manage the **Default** profile; an imported FLASH
profile is an independent snapshot and is not linked to these source files.

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

## Extension synchronization and export

Settings Sync is enabled through VS Code's account menu, not by a `settings.json`
switch. Sign in on each machine and select Settings, Keyboard Shortcuts, Snippets
and Extensions under **Settings Sync: Configure**. Also enable **UI State** to
carry over Outline placement and status bar item visibility. These choices are
stored outside `settings.json`; copying settings and keybindings alone does not
transfer them. The repository sets
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
