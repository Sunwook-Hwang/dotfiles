---
spike: 001
idea: live-external-refresh
name: live-project-refresh
type: standard
validates: "Given FLASH nvim is open in an unfocused Herdr pane, when an agent edits, creates, deletes or commits files, then the screen reflects it within a second without focusing nvim"
verdict: VALIDATED
related: []
tags: [nvim, file-watch, explorer, git, herdr]
---

# Spike 001: Live project refresh

## What This Validates
Given FLASH nvim is open in an unfocused pane, when an agent changes the project
(edit / create / delete / commit), then nvim shows it within a second without focus.

## Research
Not an nvim limitation. `vim.uv.new_fs_event()` exists and FLASH already uses it
(`lua/file_watch.lua`, per-directory, loaded buffers only; 0.13 uses native autoread).

| Approach | Pros | Cons | Status |
|---|---|---|---|
| Recursive `fs_event` on the git root | One handle, catches everything incl. `.git/index` | libuv supports `recursive` on macOS/Windows only | Prototyped, works |
| Per-directory watchers (explorer-visible dirs + `.git`) | Works on Linux | Misses changes in collapsed directories | Not built |
| Timer polling `git status` while unfocused | Universal | Cost on large repos, 1–2 s lag | Not built |

## How to Run
`recorder.lua` runs FLASH in a nested `:terminal` and logs every screen change with a
millisecond timestamp; files dropped in `$TCTL` send keys or mark actions.
`prototype.lua` is loaded inside the nested nvim with `:luafile`.

## Investigation Trail
1. Open, visible buffer, nvim unfocused: reloads in ~125 ms (in-place write, atomic
   rename, unlink+create, Claude's Edit tool). A buffer with unsaved edits is never
   reloaded (by design).
2. `before.log` (current main, unfocused): a change to an unopened file did not mark
   the explorer until a loaded buffer changed; a new file never appeared; an external
   commit did not clear marks / branch status / gutter signs; a deleted file stayed.
   All of these appeared only at FocusGained.
3. Cause: explorer listing, explorer git marks, statusline branch status and gutter
   signs refresh on `FocusGained` or on events of a loaded buffer
   (`FileChangedShellPost`, `BufWritePost`). Nothing watches the project tree or `.git`.
4. `after.log` (prototype): edit of unopened file 410 ms, new file 330 ms (+120 ms for
   its `??` mark), open-file edit 290 ms, commit 370 ms, delete 330 ms. Five refreshes
   for five actions (a commit produced 35 raw events, one refresh). 15 s idle: no
   further refreshes, so git's own index refresh does not feed back
   (`--no-optional-locks` is already used).

## Results
VALIDATED on macOS, Neovim 0.12.6. Not tested: Linux (no recursive watch), 0.13
nightly with the prototype, very large repositories, unfocused nvim in Insert mode
while the explorer re-renders.

The prototype fires a synthetic `FocusGained`; the real build should use a dedicated
event so focus-specific handlers are not triggered.
