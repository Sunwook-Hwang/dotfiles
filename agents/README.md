# Agent tools

macOS full setup (`./mac_setup.sh` or `./mac_setup.sh base`) installs these tools
after linking the dotfiles. It prepares the Claude Code and Codex CLIs first.
To install them separately, or after Linux setup:

```sh
./install_agent_tools.sh           # Codex and Claude Code tools; also Antigravity skills when agy is installed
./install_agent_tools.sh --codex   # Codex only
./install_agent_tools.sh --claude  # Claude Code only
./install_agent_tools.sh --antigravity  # Antigravity skills only
./install_agent_tools.sh --codex --claude  # Codex and Claude Code
```

This is an online installation. Installing for Codex or Claude Code requires
Node.js 24+, npm/npx, Git, and the selected agent's CLI. Both OS setup scripts
install the native Claude Code CLI when missing; `update` also updates a native
installation. The agent installer
includes `~/.local/bin` in PATH, so a newly installed CLI is available immediately.
If a CLI is outside PATH, set `CODEX_BIN` or `CLAUDE_BIN`
to its executable path. It installs for your user across projects, not into the
current project. Existing agent settings are backed up under
`~/.backup_dotfiles/<timestamp>.<unique suffix>/agent-tools/` before installation.

The default install includes the official Herdr TUI skill for Codex, Claude Code,
and Antigravity. Explicit flags select which agents receive it. Start a new
agent session inside a Herdr pane to use the skill (`HERDR_ENV=1`).
[Herdr agent skill documentation](https://herdr.dev/tui/docs/agent-skill/)

When `agy` is on PATH, the default install and `./mac_setup.sh update` also
install Archify, the Anthropic skills, and Code Simplifier in
`~/.gemini/config/skills/`. Use `--antigravity` to install these skills explicitly,
including when using only the VS Code extension. This requires Node.js 22.20.0
or newer, npm/npx, and Git. Start a new chat to pick up the skills.
You can combine this flag with `--codex`
or `--claude`.

Superpowers, Compound Engineering, and GSD have Antigravity CLI installation
paths. This option installs file-based skills for use in the VS Code extension.
Anthropic's `skill-creator` can create skills there, but its description
optimization step requires the Claude CLI.

| Tool | Installation |
| --- | --- |
| [Archify](https://github.com/tt-a1i/archify) | The `archify` skill through the upstream-recommended Skills CLI |
| [Compound Engineering](https://github.com/EveryInc/compound-engineering-plugin) | Native Codex / Claude Code plugin |
| [Karpathy guidelines](https://github.com/multica-ai/andrej-karpathy-skills) | Already included in `codex/.codex/AGENTS.md` and `claude/.claude/CLAUDE.md`; no duplicate skill |
| [GSD Core](https://github.com/open-gsd/gsd-core) | Official per-runtime installer, including its agents and hooks |
| [Anthropic skills](https://github.com/anthropics/skills) | All 19 official skills through the Skills CLI, including `webapp-testing`, document tools, frontend design, MCP building, and Claude API guidance |
| [Superpowers](https://github.com/obra/superpowers) | Official Codex / Claude plugin marketplaces; an existing installation keeps its enabled/disabled state |
| [Code Simplifier](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/code-simplifier) | Official Claude plugin; the existing Codex skill adaptation is preserved in `skills/code-simplifier/SKILL.md` and installed into the Codex skills directory |

The old `gsd-build/get-shit-done` repository redirects to GSD Core, and
`get-shit-done-cc` is deprecated. The installer uses the maintained successor.
GSD installs runtime-specific files; copying its skill folders alone is not enough.
Both `./mac_setup.sh base` and `./mac_setup.sh update` install npm's current
`latest` GSD release for Claude Code and Codex in a single installer run.
Explicit `--claude` and `--codex` agent-tool installs update only the selected runtimes.

Package selectors and source revisions are recorded in [sources.sh](sources.sh).
Superpowers follows its official marketplace version on a fresh installation;
an existing copy is kept, including when it is disabled or from another marketplace.
Code Simplifier follows the official Claude marketplace version; the Codex
adaptation is versioned in this repository. An identical installed skill is kept;
a different copy is backed up before replacement.
Claude's Compound marketplace uses a persistent checkout under
`~/.local/share/dotfiles-agent-tools/` (or `$XDG_DATA_HOME/dotfiles-agent-tools/`).
`install_dotfiles.sh` only links the existing agent guidance. macOS full setup
also runs this online installer; `link` and `unlink` do not download agent tools.
Linux setup installs the Claude CLI but leaves agent-tool installation separate.

The Anthropic collection reuses the existing `webapp-testing` installation;
it does not install a second plugin bundle containing the same skills. Its
`skill-creator` is separate from Codex's built-in system skill. The collection
also includes `discernment-nudge`, whose instructions suggest follow-up questions.

`webapp-testing` needs Python Playwright and its Chromium browser when used;
installing the skill itself does not download browsers.
