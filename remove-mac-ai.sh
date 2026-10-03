#!/bin/bash
set -euo pipefail

# RemoveMacAI-Bash
# Bash-first reimplementation of the public RemoveMacAI approach.
# Requires macOS 27 on Apple silicon.
#
# IMPORTANT:
# - This script does NOT modify /System.
# - It installs a configuration profile and invokes Apple's private
#   Unified Asset Framework through the small uaf-reset helper.
# - Run status or off --dry-run before applying changes.
#
# Usage:
#   ./remove-mac-ai.sh status
#   ./remove-mac-ai.sh features
#   ./remove-mac-ai.sh off --dry-run
#   ./remove-mac-ai.sh off
#   ./remove-mac-ai.sh off --keep siri
#   ./remove-mac-ai.sh revert

IDENTIFIER="io.github.omlahore.removemacai.bash"
PROFILE_NAME="RemoveMacAI-Bash"
PROFILE_PATH="${HOME}/Downloads/RemoveMacAI-Bash.mobileconfig"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="${SCRIPT_DIR}/uaf-reset"

FOUNDATION="com.apple.modelcatalog"
VISUAL="com.apple.MobileAsset.UAF.FM.Visual"
CODE="com.apple.MobileAsset.UAF.FM.CodeLM"
CLEANUP="com.apple.MobileAsset.UAF.Photos.MagicCleanup"
SPATIAL="com.apple.MobileAsset.UAF.Photos.SpatialPhotosRelive"

FEATURES=(
  siri
  chatgpt
  writing-tools
  genmoji
  image-playground
  mail
  notification-summaries
  messages-summaries
  safari-summaries
  notes-summaries
  inline-predictions
  spatial-photos
  photos-clean-up
  xcode-completion
)

feature_title() {
  case "$1" in
    siri) echo "Siri and Siri AI" ;;
    chatgpt) echo "ChatGPT and other AI extensions" ;;
    writing-tools) echo "Writing Tools" ;;
    genmoji) echo "Genmoji" ;;
    image-playground) echo "Image Playground" ;;
    mail) echo "Mail summaries and smart replies" ;;
    notification-summaries) echo "Notification summaries" ;;
    messages-summaries) echo "Messages summaries" ;;
    safari-summaries) echo "Safari summaries" ;;
    notes-summaries) echo "Notes transcription summaries" ;;
    inline-predictions) echo "Inline text predictions" ;;
    spatial-photos) echo "Spatial Photos" ;;
    photos-clean-up) echo "Photos Clean Up" ;;
    xcode-completion) echo "Xcode predictive code completion" ;;
    *) return 1 ;;
  esac
}

die() { echo "Error: $*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

check_platform() {
  [[ "$(uname -s)" == "Darwin" ]] || die "This utility is for macOS."
  [[ "$(uname -m)" == "arm64" ]] || die "This build targets Apple silicon (arm64)."
  local major
  major="$(sw_vers -productVersion | cut -d. -f1)"
  [[ "$major" == "27" ]] || die "Unsupported macOS version $(sw_vers -productVersion); expected macOS 27.x."
}

build_helper() {
  need_cmd clang
  if [[ -x "$HELPER" ]]; then return; fi
  echo "Building native UAF helper..."
  clang -O2 -fobjc-arc -framework Foundation     -o "$HELPER" "${SCRIPT_DIR}/uaf-reset.m" || die "Could not build uaf-reset."
  chmod 755 "$HELPER"
}

xml_escape() {
  local s="$1"
  s="${s//&/&amp;}"
  s="${s//</&lt;}"
  s="${s//>/&gt;}"
  s="${s//\"/&quot;}"
  s="${s//\'/&apos;}"
  printf '%s' "$s"
}

uuid() {
  uuidgen | tr '[:lower:]' '[:upper:]'
}

kept() {
  local x
  for x in "${KEEP[@]:-}"; do
    [[ "$x" == "$1" ]] && return 0
  done
  return 1
}

remove_foundation() {
  kept siri && return 1
  kept writing-tools && return 1
  kept genmoji && return 1
  kept image-playground && return 1
  kept mail && return 1
  kept notification-summaries && return 1
  kept messages-summaries && return 1
  kept safari-summaries && return 1
  kept notes-summaries && return 1
  return 0
}

remove_visual() {
  kept genmoji && return 1
  kept image-playground && return 1
  return 0
}

remove_spatial() { ! kept spatial-photos; }
remove_cleanup() { ! kept photos-clean-up; }
remove_code() { ! kept xcode-completion; }

append_payload_header() {
  local type="$1" suffix="$2" name="$3"
  cat <<EOF
    <dict>
      <key>PayloadType</key><string>$(xml_escape "$type")</string>
      <key>PayloadVersion</key><integer>1</integer>
      <key>PayloadIdentifier</key><string>$(xml_escape "${IDENTIFIER}.${suffix}")</string>
      <key>PayloadUUID</key><string>$(uuid)</string>
      <key>PayloadDisplayName</key><string>$(xml_escape "$name")</string>
EOF
}

append_bool_dict_entry() {
  local key="$1" value="$2"
  cat <<EOF
        <key>$(xml_escape "$key")</key><$value/>
EOF
}

append_string_dict_entry() {
  local key="$1" value="$2"
  cat <<EOF
        <key>$(xml_escape "$key")</key><string>$(xml_escape "$value")</string>
EOF
}

append_forced_payload() {
  local domain="$1" suffix="$2"
  cat <<EOF
$(append_payload_header "com.apple.ManagedClient.preferences" "preferences.${suffix}" "Forced settings: ${domain}")
      <key>PayloadContent</key>
      <dict>
        <key>$(xml_escape "$domain")</key>
        <dict>
          <key>Forced</key>
          <array>
            <dict>
              <key>mcx_preference_settings</key>
              <dict>
EOF
  case "$domain" in
    com.apple.assistant.support)
      append_bool_dict_entry "Assistant Enabled" false ;;
    com.apple.Siri)
      append_bool_dict_entry "StatusMenuVisible" false
      append_bool_dict_entry "VoiceTriggerUserEnabled" false ;;
    group.com.apple.mail)
      append_bool_dict_entry "DisableAutomaticMessageSummarization" true
      append_bool_dict_entry "PersonalizedSmartReplies" false ;;
    group.com.apple.usernoted)
      append_bool_dict_entry "summarize_previews" false ;;
    com.apple.MobileSMS)
      append_bool_dict_entry "messageSummarizationEnabled" false ;;
    .GlobalPreferences)
      append_bool_dict_entry "NSAutomaticInlinePredictionEnabled" false ;;
    com.apple.spatialphotosrelive)
      append_bool_dict_entry "LocallyDisabled" true ;;
    com.apple.MobileAsset)
      if remove_foundation; then
        append_string_dict_entry "DownloadServerBaseURLOverride-com.apple.MobileAsset.UAF.FM.GenerativeModels" "$BLOCKED_URL"
      fi
      if remove_visual; then
        append_string_dict_entry "DownloadServerBaseURLOverride-com.apple.MobileAsset.UAF.FM.Visual" "$BLOCKED_URL"
      fi
      if remove_spatial; then
        append_string_dict_entry "DownloadServerBaseURLOverride-${SPATIAL}" "$BLOCKED_URL"
      fi
      if remove_cleanup; then
        append_string_dict_entry "DownloadServerBaseURLOverride-${CLEANUP}" "$BLOCKED_URL"
      fi
      if remove_code; then
        append_string_dict_entry "DownloadServerBaseURLOverride-${CODE}" "$BLOCKED_URL"
      fi
      ;;
    "$IDENTIFIER")
      append_bool_dict_entry "installed" true
      local k
      local keep_csv=""
      for k in "${KEEP[@]:-}"; do
        [[ -n "$keep_csv" ]] && keep_csv+=","
        keep_csv+="$k"
      done
      append_string_dict_entry "kept" "$keep_csv" ;;
  esac
  cat <<EOF
              </dict>
            </dict>
          </array>
        </dict>
      </dict>
    </dict>
EOF
}

append_restrictions_payload() {
  append_payload_header "com.apple.applicationaccess" "restrictions" "Apple Intelligence restrictions"
  cat <<EOF
      <key>PayloadContent</key>
      <dict>
EOF
  ! kept siri && echo '        <key>allowAssistant</key><false/>'
  ! kept chatgpt && {
    echo '        <key>allowExternalIntelligenceIntegrations</key><false/>'
    echo '        <key>allowExternalIntelligenceIntegrationsSignIn</key><false/>'
  }
  ! kept writing-tools && echo '        <key>allowWritingTools</key><false/>'
  ! kept genmoji && echo '        <key>allowGenmoji</key><false/>'
  ! kept image-playground && echo '        <key>allowImagePlayground</key><false/>'
  ! kept mail && {
    echo '        <key>allowMailSummary</key><false/>'
    echo '        <key>allowMailSmartReplies</key><false/>'
  }
  ! kept safari-summaries && echo '        <key>allowSafariSummary</key><false/>'
  ! kept notes-summaries && echo '        <key>allowNotesTranscriptionSummary</key><false/>'
  cat <<EOF
      </dict>
    </dict>
EOF
}

make_profile() {
  BLOCKED_URL="https://127.0.0.1:9/removemacai-blocked/"
  mkdir -p "$(dirname "$PROFILE_PATH")"
  local tmp="${PROFILE_PATH}.tmp.$$"

  {
    echo '<?xml version="1.0" encoding="UTF-8"?>'
    echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    echo '<plist version="1.0"><dict>'
    echo '<key>PayloadType</key><string>Configuration</string>'
    echo '<key>PayloadVersion</key><integer>1</integer>'
    echo "<key>PayloadIdentifier</key><string>${IDENTIFIER}</string>"
    echo "<key>PayloadUUID</key><string>$(uuid)</string>"
    echo "<key>PayloadDisplayName</key><string>${PROFILE_NAME}</string>"
    echo '<key>PayloadDescription</key><string>Turns Apple Intelligence features off and blocks re-download of selected model assets. Remove this profile to undo.</string>'
    echo '<key>PayloadOrganization</key><string>RemoveMacAI-Bash</string>'
    echo '<key>PayloadScope</key><string>System</string>'
    echo '<key>PayloadRemovalDisallowed</key><false/>'
    echo '<key>PayloadContent</key><array>'

    append_restrictions_payload

    ! kept siri && append_forced_payload "com.apple.assistant.support" "assistant"
    ! kept siri && append_forced_payload "com.apple.Siri" "siri"
    ! kept mail && append_forced_payload "group.com.apple.mail" "mail"
    ! kept notification-summaries && append_forced_payload "group.com.apple.usernoted" "usernoted"
    ! kept messages-summaries && append_forced_payload "com.apple.MobileSMS" "mobilesms"
    ! kept inline-predictions && append_forced_payload ".GlobalPreferences" "global"
    ! kept spatial-photos && append_forced_payload "com.apple.spatialphotosrelive" "spatial"

    append_forced_payload "com.apple.MobileAsset" "mobileasset"
    append_forced_payload "$IDENTIFIER" "marker"

    echo '</array></dict></plist>'
  } > "$tmp"

  /usr/bin/plutil -lint "$tmp" >/dev/null || { rm -f "$tmp"; die "Generated profile failed plist validation."; }
  mv "$tmp" "$PROFILE_PATH"
}

profile_installed() {
  /usr/bin/profiles status -type configuration 2>/dev/null |
    grep -q "$IDENTIFIER"
}

print_features() {
  printf '%-24s %s\n' "ID" "FEATURE"
  printf '%-24s %s\n' "------------------------" "-----------------------------------------"
  local f
  for f in "${FEATURES[@]}"; do
    printf '%-24s %s\n' "$f" "$(feature_title "$f")"
  done
}

print_status() {
  echo "RemoveMacAI-Bash"
  echo "macOS: $(sw_vers -productVersion)"
  echo "Architecture: $(uname -m)"
  echo
  if profile_installed; then
    echo "Profile: INSTALLED"
  else
    echo "Profile: NOT INSTALLED"
  fi
  echo
  echo "Features targeted:"
  local f
  for f in "${FEATURES[@]}"; do
    printf '  %-24s OFF\n' "$f"
  done
  echo
  echo "Model sets:"
  printf '  %-52s %s\n' "$FOUNDATION" "foundation"
  printf '  %-52s %s\n' "$VISUAL" "visual"
  printf '  %-52s %s\n' "$SPATIAL" "spatial"
  printf '  %-52s %s\n' "$CLEANUP" "Photos Clean Up"
  printf '  %-52s %s\n' "$CODE" "Xcode"
  echo
  echo "Note: exact downloaded-byte accounting requires the private UAF status API."
}

parse_keep() {
  KEEP=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --keep)
        [[ $# -ge 2 ]] || die "--keep requires a feature ID"
        feature_title "$2" >/dev/null 2>&1 || die "Unknown feature: $2"
        KEEP+=("$2")
        shift 2 ;;
      --dry-run|--yes)
        shift ;;
      *) die "Unknown option: $1" ;;
    esac
  done
}

dry_run() {
  echo "DRY RUN — no changes will be made."
  echo
  echo "Would install configuration profile: $PROFILE_PATH"
  echo "Would disable:"
  local f
  for f in "${FEATURES[@]}"; do
    kept "$f" || echo "  - $(feature_title "$f") [$f]"
  done
  echo
  echo "Would request UAF ResetAssetSets for:"
  remove_foundation && echo "  - $FOUNDATION"
  remove_visual && echo "  - $VISUAL"
  remove_spatial && echo "  - $SPATIAL"
  remove_cleanup && echo "  - $CLEANUP"
  remove_code && echo "  - $CODE"
  echo
  echo "Would block re-downloads at:"
  echo "  https://127.0.0.1:9/removemacai-blocked/"
}

apply_off() {
  local auto_yes=0 dry=0
  for a in "$@"; do
    [[ "$a" == "--yes" ]] && auto_yes=1
    [[ "$a" == "--dry-run" ]] && dry=1
  done
  parse_keep "$@"
  [[ "$dry" == 1 ]] && { dry_run; return; }

  build_helper
  make_profile

  if [[ "$auto_yes" != 1 ]]; then
    echo
    echo "This will:"
    echo "  1. Install a system configuration profile."
    echo "  2. Disable selected Apple Intelligence features."
    echo "  3. Ask Apple's asset service to reset selected model sets."
    echo "  4. Block re-downloads for those sets."
    echo
    read -r -p "Continue? [y/N] " answer
    [[ "$answer" =~ ^[Yy]$ ]] || { echo "Cancelled."; return 0; }
  fi

  echo
  echo "Opening System Settings for profile approval..."
  open "x-apple.systempreferences:com.apple.Profiles-Settings.extension" || true
  echo "Approve '${PROFILE_NAME}' in System Settings."
  echo "Waiting for profile installation..."

  for _ in $(seq 1 60); do
    if profile_installed; then break; fi
    sleep 2
  done
  profile_installed || die "Profile was not detected. No asset reset was attempted."

  echo "Profile installed."
  echo "Resetting selected Apple Intelligence model asset sets..."

  local sets=()
  remove_foundation && sets+=("$FOUNDATION")
  remove_visual && sets+=("$VISUAL")
  remove_spatial && sets+=("$SPATIAL")
  remove_cleanup && sets+=("$CLEANUP")
  remove_code && sets+=("$CODE")

  if [[ "${#sets[@]}" -gt 0 ]]; then
    "$HELPER" "${sets[@]}"
  fi

  echo
  echo "Completed."
  echo "Run '$0 status' to inspect state."
}

revert() {
  if profile_installed; then
    echo "Removing configuration profile..."
    sudo /usr/bin/profiles remove -identifier "$IDENTIFIER"
  else
    echo "Profile is not installed."
  fi
  echo
  echo "Reverted. macOS may download Apple Intelligence models again when features require them."
}

main() {
  need_cmd sw_vers
  need_cmd plutil
  need_cmd profiles
  check_platform

  local cmd="${1:-status}"
  shift || true

  case "$cmd" in
    status) print_status ;;
    features) print_features ;;
    off) apply_off "$@" ;;
    revert) revert ;;
    --help|-h)
      sed -n '1,30p' "$0" ;;
    *) die "Unknown command '$cmd'. Use status, features, off, or revert." ;;
  esac
}

main "$@"
