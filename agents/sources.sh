# Public sources for agent tools and skills.
SKILLS_VERSION=1.7.4
MULTI_AGENT_SKILLS_VERSION=1.9.0
# Skill sources follow their upstream branch; reruns update only what changed.
HERDR_SKILL_SOURCE=https://github.com/herdrdev/herdr/tree/master/skills/herdr
ARCHIFY_SOURCE=https://github.com/tt-a1i/archify/tree/main/archify
ANTHROPIC_SKILLS_SOURCE=https://github.com/anthropics/skills/tree/main/skills
COMPOUND_REPOSITORY=EveryInc/compound-engineering-plugin
GSD_PACKAGE=@opengsd/gsd-core@latest
SUPERPOWERS_CODEX_PLUGIN=superpowers@openai-curated-remote
SUPERPOWERS_CLAUDE_PLUGIN=superpowers@claude-plugins-official
CODE_SIMPLIFIER_CLAUDE_PLUGIN=code-simplifier@claude-plugins-official

install_gsd() {
  # Skip the installer when every selected runtime already has npm's latest release.
  local latest runtime dir current=true
  latest=$(npm view "$GSD_PACKAGE" version)
  for runtime in "$@"; do
    if [[ "$runtime" == --codex ]]; then dir="${CODEX_HOME:-$HOME/.codex}"; else dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; fi
    [[ "$(cat "$dir/gsd-core/VERSION" 2>/dev/null)" == "$latest" ]] || current=false
  done
  if "$current"; then
    echo "GSD Core $latest is already installed."
    return
  fi
  npx --yes --prefer-online "$GSD_PACKAGE" --global "$@"
}
