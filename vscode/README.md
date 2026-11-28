# VS Code

Shared settings, FLASH-style Vim keybindings, snippets and extension IDs for
macOS and Linux. Requires VS Code; extensions are downloaded from its Marketplace.

The VS Code interface, keybindings and editing workflow are aligned as closely
as possible with [***FLASH***](../docs/flash.md).
This configuration assumes familiarity with Vim. If you are not comfortable
with Vim editing and keybindings, do not use this VS Code configuration.

The setup scripts do not copy these settings or install extensions. Import
`FLASH.code-profile` ([Transfer to another computer](#transfer-to-another-computer-including-windows)).
On macOS, setup only turns off press-and-hold for VS Code so held Vim motion
keys repeat.

## Pane navigation

`Ctrl+h/j/k/l` moves between panes. Codex and Claude Code sidebar webviews have
an explicit fallback: `Ctrl+h` returns to the editor from the right sidebar,
and `Ctrl+l` returns from the left sidebar. This follows the configured sidebar
position. Webviews opened as editor tabs retain the normal directional bindings.
Native inputs, lists, terminals and Quick Open keep their existing bindings.
In Source Control, `Ctrl+j/k` moves between Changes and Graph; `Ctrl+n/p` moves within each list.
`Ctrl+;` returns to the active editor group from any view, opening an untitled
buffer if the group is empty, read-only, or displays a non-text page such as extension details.
Existing editable text and diff editors are kept. Space remains the leader key in Vim editing modes.
`Ctrl+Shift+1/2/3` toggles Codex, Claude Code, and Antigravity; `Ctrl+Shift+0` toggles Chat Sessions. `Ctrl+Shift+T` also toggles Codex. The FLASH profile places Antigravity in the right sidebar.
Use `Ctrl+L` from the editor to focus the Antigravity chat and `Ctrl+;` to return.
Antigravity inline comments are disabled by default. Enable them with `antigravity.enableComments`.

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
An imported FLASH profile is an independent snapshot and is not linked to these
source files. `VSCODE_USER_DIR` selects the VS Code user directory it reads.

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

To refresh `extensions.txt`, run `./vscode/export_extensions.sh`. Add `--update`
to update installed extensions first. Setup scripts do not run it.

This exports the Default profile's installed extension IDs, including disabled
extensions, as a sorted list. It excludes the internal `openai.codex-audio`
integration and does not export installation paths or credentials. Review the
list for any other private extensions before publishing. `CODE_BIN` selects a
specific VS Code CLI. Named profiles and remote SSH/WSL extensions are not
included in this Default-profile snapshot.

A failed CLI query or invalid output preserves the existing file. Review
`git diff -- vscode/extensions.txt`, then commit when ready. Export alone does not
install, uninstall, commit or push anything.

## Private data

Only settings, keybindings, snippets and public extension IDs are included.
Accounts, credentials, cloud project IDs, local paths, profile IDs, caches and
runtime databases are excluded. Automatic workspace/notebook trust overrides
are also omitted. Keep machine-specific settings and credentials outside this
repository. Do not add them to repository settings unless they are safe to
publish.
