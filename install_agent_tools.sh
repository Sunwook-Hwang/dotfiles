#!/usr/bin/env bash
# Online, user-scoped installation; ordinary dotfiles linking stays offline.
set -euo pipefail

CURDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURDIR/agents/sources.sh"
export PATH="$HOME/.local/bin:$PATH"

install_codex=false
install_claude=false
if [[ "$#" -eq 0 ]]; then
  install_codex=true
  install_claude=true
fi
for option in "$@"; do
  case "$option" in
  --codex) install_codex=true ;;
  --claude) install_claude=true ;;
  *) echo "Usage: $0 [--codex] [--claude]" >&2; exit 1 ;;
  esac
done
runtimes=()
skill_agents=()
if "$install_codex"; then runtimes+=(codex); skill_agents+=(codex); fi
if "$install_claude"; then runtimes+=(claude); skill_agents+=(claude-code); fi
[[ "${EUID:-$(id -u)}" -ne 0 ]] || { echo "Run this script as your normal user, without sudo." >&2; exit 1; }

for executable in node npm npx git; do
  command -v "$executable" >/dev/null 2>&1 || { echo "Required command not found: $executable" >&2; exit 1; }
done
node -e 'if (Number(process.versions.node.split(".")[0]) < 24) { console.error("GSD Core requires Node.js 24 or newer."); process.exit(1); }'

CODEX_BIN="${CODEX_BIN:-codex}"
CLAUDE_BIN="${CLAUDE_BIN:-claude}"
for runtime in "${runtimes[@]}"; do
  if [[ "$runtime" == codex ]]; then executable="$CODEX_BIN"; else executable="$CLAUDE_BIN"; fi
  command -v "$executable" >/dev/null 2>&1 || { echo "$runtime CLI not found: $executable. Install it or select the other runtime." >&2; exit 1; }
done

mkdir -p "$HOME/.backup_dotfiles"
backup="$(mktemp -d "$HOME/.backup_dotfiles/$(date +%Y%m%d%H%M%S).XXXXXX")/agent-tools"
stage=""
trap '[[ -z "$stage" ]] || rm -rf "$stage"' EXIT
for runtime in "${runtimes[@]}"; do
  if [[ "$runtime" == codex ]]; then
    config="${CODEX_HOME:-$HOME/.codex}/config.toml"
  else
    config="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
  fi
  if [[ -e "$config" ]]; then
    mkdir -p "$backup/$runtime"
    cp -L "$config" "$backup/$runtime/$(basename "$config")"
    echo "Backed up $config -> $backup/$runtime"
  fi
done

DISABLE_TELEMETRY=1 npx --yes "skills@$SKILLS_VERSION" add "$ARCHIFY_SOURCE" --global --agent "${skill_agents[@]}" --yes
DISABLE_TELEMETRY=1 npx --yes "skills@$SKILLS_VERSION" add "$ANTHROPIC_SKILLS_SOURCE" --skill '*' --global --agent "${skill_agents[@]}" --yes

has_superpowers() {
  node -e 'const data = JSON.parse(require("fs").readFileSync(0, "utf8"));
    const plugins = Array.isArray(data) ? data : data.installed;
    if (!Array.isArray(plugins)) throw new Error("Invalid plugin list");
    process.stdout.write(String(plugins.some(p => p.installed !== false &&
      (p.name === "superpowers" || (p.pluginId || p.id || "").startsWith("superpowers@")))));'
}

for runtime in "${runtimes[@]}"; do
  if [[ "$runtime" == codex ]]; then
    installed_plugins=$("$CODEX_BIN" plugin list --json)
    superpowers_installed=$(printf '%s\n' "$installed_plugins" | has_superpowers)
    skill_dir="${CODEX_HOME:-$HOME/.codex}/skills/code-simplifier"
    skill_source="$CURDIR/agents/skills/code-simplifier/SKILL.md"
    if ! cmp -s "$skill_source" "$skill_dir/SKILL.md"; then
      if [[ -e "$skill_dir/SKILL.md" ]]; then
        mkdir -p "$backup/codex/code-simplifier"
        cp -L "$skill_dir/SKILL.md" "$backup/codex/code-simplifier/SKILL.md"
      fi
      mkdir -p "$skill_dir"
      cp "$skill_source" "$skill_dir/SKILL.md"
    fi
    if [[ "$superpowers_installed" == true ]]; then
      echo "Codex Superpowers already installed; preserving its enabled/disabled state."
    else
      "$CODEX_BIN" plugin add "$SUPERPOWERS_CODEX_PLUGIN"
    fi
    "$CODEX_BIN" plugin marketplace add "$COMPOUND_REPOSITORY" --ref "$COMPOUND_REVISION"
    "$CODEX_BIN" plugin add compound-engineering@compound-engineering-plugin
  else
    installed_plugins=$("$CLAUDE_BIN" plugin list --json)
    superpowers_installed=$(printf '%s\n' "$installed_plugins" | has_superpowers)
    "$CLAUDE_BIN" plugin marketplace add anthropics/claude-plugins-official --scope user
    if [[ "$superpowers_installed" == true ]]; then
      echo "Claude Superpowers already installed; preserving its enabled/disabled state."
    else
      "$CLAUDE_BIN" plugin install "$SUPERPOWERS_CLAUDE_PLUGIN" --scope user
    fi
    "$CLAUDE_BIN" plugin install "$CODE_SIMPLIFIER_CLAUDE_PLUGIN" --scope user
    # Claude's Git URL installer accepts branches/tags, not a detached commit.
    cache="${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles-agent-tools/compound-engineering/$COMPOUND_REVISION"
    if [[ ! -d "$cache" ]]; then
      mkdir -p "$(dirname "$cache")"
      stage=$(mktemp -d "$(dirname "$cache")/.compound.XXXXXX")
      git init --quiet "$stage"
      git -C "$stage" fetch --quiet --depth 1 "https://github.com/$COMPOUND_REPOSITORY.git" "$COMPOUND_REVISION"
      git -C "$stage" checkout --quiet --detach FETCH_HEAD
      mv "$stage" "$cache"
      stage=""
    fi
    "$CLAUDE_BIN" plugin marketplace add "$cache" --scope user
    "$CLAUDE_BIN" plugin install compound-engineering@compound-engineering-plugin --scope user
  fi
  npx --yes "$GSD_PACKAGE" "--$runtime" --global
done

echo "Agent tools installed. Karpathy guidance is already in the tracked AGENTS.md / CLAUDE.md."
echo "Start a new Codex or Claude Code session to load the new tools."
