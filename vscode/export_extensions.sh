#!/usr/bin/env bash
# Export extensions on demand, optionally updating installed extensions first.
set -euo pipefail

CURDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "${1:-}" in
"" | --update) ;;
*)
  echo "Usage: $0 [--update]" >&2
  exit 1
  ;;
esac
if [[ "$#" -gt 1 ]]; then
  echo "Usage: $0 [--update]" >&2
  exit 1
fi
code_bin=${CODE_BIN:-}
if [[ -z "$code_bin" ]]; then
  if command -v code >/dev/null 2>&1; then
    code_bin=code
  elif [[ -x '/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code' ]]; then
    code_bin='/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code'
  elif [[ -x "$HOME/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" ]]; then
    code_bin="$HOME/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
  else
    if [[ "${1:-}" == --update ]]; then
      echo 'VS Code CLI not found; skipping extension update and export.'
      exit 0
    fi
    echo 'VS Code CLI not found; install VS Code or set CODE_BIN.' >&2
    exit 1
  fi
fi

if [[ "${1:-}" == --update ]]; then
  echo 'Updating installed VS Code extensions...'
  "$code_bin" --update-extensions
fi

# Capture successfully before touching the existing manifest.
installed_extensions=$("$code_bin" --list-extensions)
temporary=$(mktemp "$CURDIR/.extensions.txt.XXXXXX")
trap 'rm -f "$temporary"' EXIT
printf '%s\n' "$installed_extensions" |
  tr '[:upper:]' '[:lower:]' | tr -d '\r' |
  sed '/^$/d; /^openai\.codex-audio$/d' |
  LC_ALL=C sort -u >"$temporary"
if LC_ALL=C grep -qEv '^[a-z0-9-]+\.[a-z0-9-]+$' "$temporary"; then
  echo 'Invalid VS Code extension list; existing manifest preserved.' >&2
  exit 1
fi
if cmp -s "$temporary" "$CURDIR/extensions.txt"; then
  echo "VS Code extension list unchanged: $CURDIR/extensions.txt"
else
  chmod 644 "$temporary"
  mv "$temporary" "$CURDIR/extensions.txt"
  echo "VS Code extension list exported: $CURDIR/extensions.txt ($(wc -l <"$CURDIR/extensions.txt" | tr -d ' ') extensions)"
fi
