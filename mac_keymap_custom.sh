#!/bin/sh
# Standalone macOS key remaps via hidutil.
#   Right Command -> F18 (bind F18 to "Select next source in Input menu" for Korean/English)
#   Caps Lock     -> Left Control
# on:  apply now and at every login (per-user LaunchAgent); input-source shortcuts: ^Space off, F18 = next source
# off: remove the LaunchAgent, clear the remaps and restore the macOS default shortcuts
set -eu

mapping='{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x7000000E7,"HIDKeyboardModifierMappingDst":0x70000006D},{"HIDKeyboardModifierMappingSrc":0x700000039,"HIDKeyboardModifierMappingDst":0x7000000E0}]}'
label=com.sunwook.keymap
plist="$HOME/Library/LaunchAgents/$label.plist"
domain="gui/$(id -u)"

# Shortcut 60 "Select the previous input source", 61 "Select next source in Input menu".
set_input_shortcuts() {
  defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 60 \
    "{ enabled = $1; value = { parameters = ($2); type = standard; }; }"
  defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 61 \
    "{ enabled = $3; value = { parameters = ($4); type = standard; }; }"
  /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
}

case "${1:-}" in
on)
  mkdir -p "$(dirname "$plist")"
  cat >"$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key>
  <array><string>/usr/bin/hidutil</string><string>property</string><string>--set</string><string>$mapping</string></array>
  <key>RunAtLoad</key><true/>
</dict>
</plist>
PLIST
  launchctl bootout "$domain/$label" 2>/dev/null || true
  launchctl bootstrap "$domain" "$plist"
  # ^Space off; F18 (key code 79, fn flag) = next source.
  set_input_shortcuts 0 '32, 49, 262144' 1 '65535, 79, 8388608'
  echo "Keymap on"
  ;;
off)
  launchctl bootout "$domain/$label" 2>/dev/null || true
  rm -f "$plist"
  hidutil property --set '{"UserKeyMapping":[]}' >/dev/null
  # macOS defaults: ^Space = previous source, ^⌥Space = next source.
  set_input_shortcuts 1 '32, 49, 262144' 1 '32, 49, 786432'
  echo "Keymap off"
  ;;
*)
  echo "Usage: ${0##*/} on|off" >&2
  exit 1
  ;;
esac
