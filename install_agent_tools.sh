#!/usr/bin/env bash
# Online, user-scoped installation; ordinary dotfiles linking stays offline.
set -euo pipefail

CURDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURDIR/agents/sources.sh"
export PATH="$HOME/.local/bin:$PATH"

install_codex=false
install_claude=false
install_antigravity=false
if [[ "$#" -eq 0 ]]; then
  install_codex=true
  install_claude=true
  if command -v agy >/dev/null 2>&1; then install_antigravity=true; fi
fi
for option in "$@"; do
  case "$option" in
  --codex) install_codex=true ;;
  --claude) install_claude=true ;;
  --antigravity) install_antigravity=true ;;
  *) echo "Usage: $0 [--codex] [--claude] [--antigravity]" >&2; exit 1 ;;
  esac
done
runtimes=()
skill_agents=()
if "$install_codex"; then runtimes+=(codex); skill_agents+=(codex); fi
if "$install_claude"; then runtimes+=(claude); skill_agents+=(claude-code); fi
[[ "${EUID:-$(id -u)}" -ne 0 ]] || { echo "Run this script as your normal user, without sudo." >&2; exit 1; }

backup=""
backup_setting() {
  local runtime="$1" config="$2"
  if [[ ! -e "$config" ]]; then
    [[ ! -L "$config" ]] || { echo "Broken settings link: $config" >&2; return 1; }
    return 0
  fi
  if [[ -z "$backup" ]]; then
    mkdir -p "$HOME/.backup_dotfiles"
    backup="$(mktemp -d "$HOME/.backup_dotfiles/$(date +%Y%m%d%H%M%S).XXXXXX")/agent-tools"
  fi
  mkdir -p "$backup/$runtime"
  cp -L "$config" "$backup/$runtime/.copying"
  cmp -s "$config" "$backup/$runtime/.copying" || { echo "Backup verification failed: $config" >&2; return 1; }
  mv "$backup/$runtime/.copying" "$backup/$runtime/${config##*/}"
  echo "Backed up $config -> $backup/$runtime/${config##*/}"
}

if "$install_codex"; then
  backup_setting codex "${CODEX_HOME:-$HOME/.codex}/config.toml"
  backup_setting codex "${CODEX_HOME:-$HOME/.codex}/config.local.toml"
fi
if "$install_claude"; then
  backup_setting claude "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
  backup_setting claude "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.local.json"
fi

for executable in node npm npx git; do
  command -v "$executable" >/dev/null 2>&1 || { echo "Required command not found: $executable" >&2; exit 1; }
done

skills_state="${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles-agent-tools/skills"

# Succeeds when some of the given agents lack the skill or have an older upstream
# commit, and lists them in outdated_agents. Usage: skills_outdated SKILL SOURCE AGENT...
skills_outdated() {
  local name=$1 source=$2 agent dir
  shift 2
  local repository=${source%%/tree/*} branch=${source#*/tree/}
  skills_commit=$(git ls-remote "$repository" "refs/heads/${branch%%/*}" | cut -f1)
  [[ -n "$skills_commit" ]] || { echo "Could not read the latest commit of $repository." >&2; exit 1; }
  outdated_agents=()
  for agent in "$@"; do
    case "$agent" in
    codex) dir="$HOME/.agents/skills" ;;
    claude-code) dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills" ;;
    antigravity) dir="$HOME/.gemini/config/skills" ;;
    esac
    if [[ -d "$dir/$name" && "$(cat "$skills_state/$agent/$name" 2>/dev/null)" == "$skills_commit" ]]; then continue; fi
    outdated_agents+=("$agent")
  done
  if [[ "${#outdated_agents[@]}" -eq 0 ]]; then
    echo "$name skills are already up to date."
    return 1
  fi
}

# Records the commit that skills_outdated found for the agents it listed.
skills_synced() {
  local agent
  for agent in "${outdated_agents[@]}"; do
    mkdir -p "$skills_state/$agent"
    printf '%s\n' "$skills_commit" >"$skills_state/$agent/$1"
  done
}

install_herdr_skill() {
  if skills_outdated herdr "$HERDR_SKILL_SOURCE" "$@"; then
    DISABLE_TELEMETRY=1 npx --yes "skills@$MULTI_AGENT_SKILLS_VERSION" add "$HERDR_SKILL_SOURCE" --skill herdr --global --agent "${outdated_agents[@]}" --yes
    skills_synced herdr
  fi
}

install_antigravity_skills() {
  # Use a version that supports Antigravity's current global skills directory.
  local flags=(--global --agent antigravity --copy --yes)
  local simplifier="$CURDIR/agents/skills/code-simplifier"
  if skills_outdated archify "$ARCHIFY_SOURCE" antigravity; then
    DISABLE_TELEMETRY=1 npx --yes "skills@$MULTI_AGENT_SKILLS_VERSION" add "$ARCHIFY_SOURCE" "${flags[@]}"
    skills_synced archify
  fi
  # skill-creator stands for the whole Anthropic collection.
  if skills_outdated skill-creator "$ANTHROPIC_SKILLS_SOURCE" antigravity; then
    DISABLE_TELEMETRY=1 npx --yes "skills@$MULTI_AGENT_SKILLS_VERSION" add "$ANTHROPIC_SKILLS_SOURCE" --skill '*' "${flags[@]}"
    skills_synced skill-creator
  fi
  if ! cmp -s "$simplifier/SKILL.md" "$HOME/.gemini/config/skills/code-simplifier/SKILL.md"; then
    DISABLE_TELEMETRY=1 npx --yes "skills@$MULTI_AGENT_SKILLS_VERSION" add "$simplifier" "${flags[@]}"
  fi
  echo "Start a new Antigravity chat to load the installed skills."
}

if "$install_antigravity" && ! "$install_codex" && ! "$install_claude"; then
  install_herdr_skill antigravity
  install_antigravity_skills
  exit 0
fi

node -e 'if (Number(process.versions.node.split(".")[0]) < 24) { console.error("GSD Core requires Node.js 24 or newer."); process.exit(1); }'

CODEX_BIN="${CODEX_BIN:-codex}"
CLAUDE_BIN="${CLAUDE_BIN:-claude}"
for runtime in "${runtimes[@]}"; do
  if [[ "$runtime" == codex ]]; then executable="$CODEX_BIN"; else executable="$CLAUDE_BIN"; fi
  command -v "$executable" >/dev/null 2>&1 || { echo "$runtime CLI not found: $executable. Install it or select the other runtime." >&2; exit 1; }
done

herdr_agents=("${skill_agents[@]}")
if [[ "$#" -eq 0 ]] || "$install_antigravity"; then herdr_agents+=(antigravity); fi
install_herdr_skill "${herdr_agents[@]}"

if skills_outdated archify "$ARCHIFY_SOURCE" "${skill_agents[@]}"; then
  DISABLE_TELEMETRY=1 npx --yes "skills@$SKILLS_VERSION" add "$ARCHIFY_SOURCE" --global --agent "${outdated_agents[@]}" --yes
  skills_synced archify
fi
# skill-creator stands for the whole Anthropic collection.
if skills_outdated skill-creator "$ANTHROPIC_SKILLS_SOURCE" "${skill_agents[@]}"; then
  DISABLE_TELEMETRY=1 npx --yes "skills@$SKILLS_VERSION" add "$ANTHROPIC_SKILLS_SOURCE" --skill '*' --global --agent "${outdated_agents[@]}" --yes
  skills_synced skill-creator
fi

# Prints the installed plugin IDs named $1 from a plugin list JSON on stdin.
installed_plugins() {
  node -e 'const data = JSON.parse(require("fs").readFileSync(0, "utf8"));
    const plugins = Array.isArray(data) ? data : data.installed;
    if (!Array.isArray(plugins)) throw new Error("Invalid plugin list");
    for (const p of plugins) {
      const id = p.pluginId || p.id || "";
      if (p.installed !== false && id.split("@")[0] === process.argv[1]) console.log(id);
    }' "$1"
}

# Installs the Claude plugin $2 when no plugin named $1 exists; otherwise updates
# each installed copy in place, which keeps its marketplace and enabled state.
claude_plugin() {
  local ids id
  ids=$("$CLAUDE_BIN" plugin list --json | installed_plugins "$1")
  if [[ -z "$ids" ]]; then
    "$CLAUDE_BIN" plugin install "$2" --scope user
    return
  fi
  while read -r id; do
    "$CLAUDE_BIN" plugin update "$id" --scope user
  done <<<"$ids"
}

for runtime in "${runtimes[@]}"; do
  if [[ "$runtime" == codex ]]; then
    skill_dir="${CODEX_HOME:-$HOME/.codex}/skills/code-simplifier"
    skill_source="$CURDIR/agents/skills/code-simplifier/SKILL.md"
    if ! cmp -s "$skill_source" "$skill_dir/SKILL.md"; then
      if [[ -e "$skill_dir/SKILL.md" ]]; then
        backup_setting codex/code-simplifier "$skill_dir/SKILL.md"
      fi
      mkdir -p "$skill_dir"
      cp "$skill_source" "$skill_dir/SKILL.md"
    fi
    # Codex has no plugin update command; its remote marketplace copy is kept.
    plugins=$("$CODEX_BIN" plugin list --json)
    superpowers=$(installed_plugins superpowers <<<"$plugins")
    if [[ -n "$superpowers" ]]; then
      echo "Codex Superpowers already installed; preserving it."
    elif output=$("$CODEX_BIN" plugin add "$SUPERPOWERS_CODEX_PLUGIN" 2>&1); then
      printf '%s\n' "$output"
    else
      status=$?
      case "$output" in
        *"authentication required for remote plugin catalog"*)
          echo "Installing Superpowers from its public Git marketplace."
          "$CODEX_BIN" plugin marketplace add obra/superpowers
          "$CODEX_BIN" plugin add superpowers@superpowers-dev
          ;;
        *) printf '%s\n' "$output" >&2; exit "$status" ;;
      esac
    fi
    # A marketplace from an older run is pinned to a commit; replace it to follow upstream.
    snapshot="${CODEX_HOME:-$HOME/.codex}/.tmp/marketplaces/compound-engineering-plugin"
    before=$(git -C "$snapshot" rev-parse HEAD 2>/dev/null || true)
    if ! "$CODEX_BIN" plugin marketplace add "$COMPOUND_REPOSITORY"; then
      "$CODEX_BIN" plugin marketplace remove compound-engineering-plugin
      "$CODEX_BIN" plugin marketplace add "$COMPOUND_REPOSITORY"
    fi
    "$CODEX_BIN" plugin marketplace upgrade compound-engineering-plugin
    compound=$(installed_plugins compound-engineering <<<"$plugins")
    if [[ -z "$compound" ||
      "$(git -C "$snapshot" rev-parse HEAD 2>/dev/null || true)" != "$before" ]]; then
      "$CODEX_BIN" plugin add compound-engineering@compound-engineering-plugin
    fi
  else
    "$CLAUDE_BIN" plugin marketplace add anthropics/claude-plugins-official --scope user
    "$CLAUDE_BIN" plugin marketplace update claude-plugins-official
    claude_plugin superpowers "$SUPERPOWERS_CLAUDE_PLUGIN"
    claude_plugin code-simplifier "$CODE_SIMPLIFIER_CLAUDE_PLUGIN"
    # A marketplace from an older run is a local checkout of one commit; replace it to follow upstream.
    if ! "$CLAUDE_BIN" plugin marketplace add "$COMPOUND_REPOSITORY" --scope user; then
      "$CLAUDE_BIN" plugin marketplace remove compound-engineering-plugin
      "$CLAUDE_BIN" plugin marketplace add "$COMPOUND_REPOSITORY" --scope user
    fi
    "$CLAUDE_BIN" plugin marketplace update compound-engineering-plugin
    claude_plugin compound-engineering compound-engineering@compound-engineering-plugin
  fi
done
install_gsd "${runtimes[@]/#/--}"

if "$install_antigravity"; then
  install_antigravity_skills
fi
echo "Agent tools installed. Karpathy guidance is already in the tracked AGENTS.md / CLAUDE.md / GEMINI.md."
echo "Start a new Codex or Claude Code session to load the new tools."
