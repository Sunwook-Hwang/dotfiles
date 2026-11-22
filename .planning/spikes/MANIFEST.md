# Spike Manifest

## Ideas

### live-external-refresh
FLASH nvim sitting in an unfocused Herdr pane should show what agents change in the
project immediately, like VS Code: buffer text, explorer entries, git marks, branch
status and gutter signs.

**Requirements:**

- Must update without focusing the nvim pane.
- Must stay within FLASH's no-plugin rule (native `vim.uv` only).
- Must never reload a buffer that has unsaved edits.

## Spikes

| # | Idea | Name | Type | Validates | Verdict | Tags |
|---|------|------|------|-----------|---------|------|
| 001 | live-external-refresh | live-project-refresh | standard | Unfocused nvim reflects external edit/create/delete/commit within a second | VALIDATED | nvim, file-watch, explorer, git, herdr |
