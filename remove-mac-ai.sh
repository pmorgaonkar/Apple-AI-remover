#!/bin/bash
set -euo pipefail

readonly VERSION='0.3.0'
readonly PRODUCT_NAME='Apple AI remover'
readonly PROFILE_ID='io.github.pmorgaonkar.apple-ai-remover'
readonly LEGACY_PROFILE_ID='io.github.omlahore.removemacai.bash'
readonly UPSTREAM_PROFILE_ID='io.github.omlahore.removemacai'
readonly PROFILE_NAME='Apple AI remover'
readonly PROFILE_FILE="$HOME/Downloads/Apple-AI-remover.mobileconfig"
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly HELPER_SOURCE="$SCRIPT_DIR/uaf-reset.m"
readonly BUILD_SCRIPT="$SCRIPT_DIR/build-helper.sh"
readonly TARGET_MAJOR=27
readonly BLOCKED_URL='https://127.0.0.1:9/apple-ai-remover-blocked/'

MODEL_SETS=(
  'com.apple.modelcatalog'
  'com.apple.MobileAsset.UAF.FM.Visual'
  'com.apple.MobileAsset.UAF.Photos.SpatialPhotosRelive'
  'com.apple.MobileAsset.UAF.Photos.MagicCleanup'
  'com.apple.MobileAsset.UAF.FM.CodeLM'
)
FEATURES=(
  siri chatgpt writing-tools genmoji image-playground mail
  notification-summaries messages-summaries safari-summaries notes-summaries
  inline-predictions spatial-photos photos-clean-up xcode-completion
)
KEEP=()
HELPER_DIR=''
HELPER=''
DRY_RUN=0
YES=0

fail() { printf 'error: %s\n' "$*" >&2; exit 1; }
info() { printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"; }

require_platform() {
  [[ "$(uname -s)" == Darwin ]] || fail 'this utility runs on macOS'
  [[ "$(uname -m)" == arm64 ]] || fail 'this build targets Apple silicon (arm64)'
  local version="$(sw_vers -productVersion)"
  local major="${version%%.*}"
  [[ "$major" == "$TARGET_MAJOR" ]] || fail "unsupported macOS $version; this release targets macOS $TARGET_MAJOR.x"
}

cleanup_helper() {
  [[ -z "$HELPER_DIR" ]] || rm -rf "$HELPER_DIR"
}

build_helper() {
  need_cmd clang
  need_cmd mktemp
  [[ -r "$HELPER_SOURCE" ]] || fail "missing native helper source: $HELPER_SOURCE"
  [[ -x "$BUILD_SCRIPT" ]] || fail "missing executable build script: $BUILD_SCRIPT"
  if [[ -n "$HELPER" && -x "$HELPER" ]]; then return 0; fi
  HELPER_DIR="$(mktemp -d "${TMPDIR:-/tmp}/apple-ai-remover.XXXXXX")"
  HELPER="$HELPER_DIR/uaf-reset"
  trap cleanup_helper EXIT HUP INT TERM
  "$BUILD_SCRIPT" "$HELPER" >/dev/null
  [[ -x "$HELPER" ]] || fail 'native helper build produced no executable'
}

feature_exists() {
  local f
  for f in "${FEATURES[@]}"; do [[ "$f" == "$1" ]] && return 0; done
  return 1
}

feature_title() {
  case "$1" in
    siri) echo 'Siri and Siri AI' ;;
    chatgpt) echo 'ChatGPT and other AI extensions' ;;
    writing-tools) echo 'Writing Tools' ;;
    genmoji) echo 'Genmoji' ;;
    image-playground) echo 'Image Playground' ;;
    mail) echo 'Mail summaries and smart replies' ;;
    notification-summaries) echo 'Notification summaries' ;;
    messages-summaries) echo 'Messages summaries' ;;
    safari-summaries) echo 'Safari summaries' ;;
    notes-summaries) echo 'Notes transcription summaries' ;;
    inline-predictions) echo 'Inline text predictions' ;;
    spatial-photos) echo 'Spatial Photos' ;;
    photos-clean-up) echo 'Photos Clean Up' ;;
    xcode-completion) echo 'Xcode predictive code completion' ;;
    *) return 1 ;;
  esac
}

feature_restrictions() {
  case "$1" in
    siri) printf '%s\n' allowAssistant ;;
    chatgpt) printf '%s\n' allowExternalIntelligenceIntegrations allowExternalIntelligenceIntegrationsSignIn ;;
    writing-tools) printf '%s\n' allowWritingTools ;;
    genmoji) printf '%s\n' allowGenmoji ;;
    image-playground) printf '%s\n' allowImagePlayground ;;
    mail) printf '%s\n' allowMailSummary allowMailSmartReplies ;;
    safari-summaries) printf '%s\n' allowSafariSummary ;;
    notes-summaries) printf '%s\n' allowNotesTranscriptionSummary ;;
  esac
}

feature_preferences() {
  case "$1" in
    siri)
      printf '%s\t%s\t%s\n' com.apple.assistant.support 'Assistant Enabled' false
      printf '%s\t%s\t%s\n' com.apple.Siri StatusMenuVisible false
      printf '%s\t%s\t%s\n' com.apple.Siri VoiceTriggerUserEnabled false ;;
    mail)
      printf '%s\t%s\t%s\n' group.com.apple.mail DisableAutomaticMessageSummarization true
      printf '%s\t%s\t%s\n' group.com.apple.mail PersonalizedSmartReplies false ;;
    notification-summaries)
      printf '%s\t%s\t%s\n' group.com.apple.usernoted summarize_previews false ;;
    messages-summaries)
      printf '%s\t%s\t%s\n' com.apple.MobileSMS messageSummarizationEnabled false ;;
    inline-predictions)
      printf '%s\t%s\t%s\n' .GlobalPreferences NSAutomaticInlinePredictionEnabled false ;;
    spatial-photos)
      printf '%s\t%s\t%s\n' com.apple.spatialphotosrelive LocallyDisabled true ;;
  esac
}

feature_model_sets() {
  case "$1" in
    siri|writing-tools|mail|notification-summaries|messages-summaries|safari-summaries|notes-summaries)
      printf '%s\n' com.apple.modelcatalog ;;
    genmoji|image-playground)
      printf '%s\n' com.apple.modelcatalog com.apple.MobileAsset.UAF.FM.Visual ;;
    spatial-photos) printf '%s\n' com.apple.MobileAsset.UAF.Photos.SpatialPhotosRelive ;;
    photos-clean-up) printf '%s\n' com.apple.MobileAsset.UAF.Photos.MagicCleanup ;;
    xcode-completion) printf '%s\n' com.apple.MobileAsset.UAF.FM.CodeLM ;;
  esac
}

model_set_asset_type() {
  case "$1" in
    com.apple.modelcatalog) echo com.apple.MobileAsset.UAF.FM.GenerativeModels ;;
    com.apple.MobileAsset.UAF.FM.Visual) echo com.apple.MobileAsset.UAF.FM.Visual ;;
    com.apple.MobileAsset.UAF.Photos.SpatialPhotosRelive) echo com.apple.MobileAsset.UAF.Photos.SpatialPhotosRelive ;;
    com.apple.MobileAsset.UAF.Photos.MagicCleanup) echo com.apple.MobileAsset.UAF.Photos.MagicCleanup ;;
    com.apple.MobileAsset.UAF.FM.CodeLM) echo com.apple.MobileAsset.UAF.FM.CodeLM ;;
    *) return 1 ;;
  esac
}

model_set_title() {
  case "$1" in
    com.apple.modelcatalog) echo 'Apple Intelligence foundation models' ;;
    com.apple.MobileAsset.UAF.FM.Visual) echo 'Image and Genmoji models' ;;
    com.apple.MobileAsset.UAF.Photos.SpatialPhotosRelive) echo 'Spatial Photos models' ;;
    com.apple.MobileAsset.UAF.Photos.MagicCleanup) echo 'Photos Clean Up models' ;;
    com.apple.MobileAsset.UAF.FM.CodeLM) echo 'Xcode code completion models' ;;
    *) return 1 ;;
  esac
}

kept() {
  local item
  for item in "${KEEP[@]}"; do [[ "$item" == "$1" ]] && return 0; done
  return 1
}

parse_keep_value() {
  local raw="$1" item old_ifs="$IFS"
  local -a items
  IFS=','
  read -r -a items <<< "$raw"
  IFS="$old_ifs"
  for item in "${items[@]}"; do
    item="$(printf '%s' "$item" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -n "$item" ]] && feature_exists "$item" || { [[ -z "$item" ]] || fail "unknown feature '$item'"; }
    [[ -z "$item" ]] || { kept "$item" || KEEP=("${KEEP[@]}" "$item"); }
  done
}

parse_args() {
  KEEP=()
  DRY_RUN=0
  YES=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --keep)
        [[ $# -ge 2 ]] || fail '--keep requires a feature name or comma-separated list'
        parse_keep_value "$2"; shift 2 ;;
      --dry-run) DRY_RUN=1; shift ;;
      --yes|-y) YES=1; shift ;;
      *) fail "unknown option '$1'" ;;
    esac
  done
}

model_set_users() {
  local target="$1" feature set
  for feature in "${FEATURES[@]}"; do
    while IFS= read -r set; do
      [[ "$set" == "$target" ]] && printf '%s\n' "$feature"
    done < <(feature_model_sets "$feature")
  done
}

sets_to_remove() {
  local target user
  for target in "${MODEL_SETS[@]}"; do
    local remove=1
    while IFS= read -r user; do
      kept "$user" && { remove=0; break; }
    done < <(model_set_users "$target")
    (( remove == 1 )) && printf '%s\n' "$target"
  done
  return 0
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

stable_uuid() {
  local name="$1" hash variant
  hash="$(printf '%s' "$name" | shasum -a 1 | awk '{print $1}')"
  variant=$((16#${hash:16:2} & 63 | 128))
  printf '%s-%s-%s-%s-%s\n' "${hash:0:8}" "${hash:8:4}" "5${hash:13:3}" "$(printf '%02x' "$variant")${hash:18:2}" "${hash:20:12}"
}

payload_header() {
  local type="$1" suffix="$2" title="$3" id="$PROFILE_ID.$suffix"
  cat <<EOF
    <dict>
      <key>PayloadType</key><string>$(xml_escape "$type")</string>
      <key>PayloadVersion</key><integer>1</integer>
      <key>PayloadIdentifier</key><string>$(xml_escape "$id")</string>
      <key>PayloadUUID</key><string>$(stable_uuid "$id")</string>
      <key>PayloadDisplayName</key><string>$(xml_escape "$title")</string>
EOF
}

emit_preferences_payload() {
  local domain="$1" suffix="$2" title="$3" lines="$4"
  [[ -n "$lines" ]] || return 0
  payload_header com.apple.ManagedClient.preferences "preferences.$suffix" "$title"
  printf '%s\n' '      <key>PayloadContent</key><dict>'
  printf '        <key>%s</key>\n' "$(xml_escape "$domain")"
  printf '%s\n' '        <dict><key>Forced</key><array><dict><key>mcx_preference_settings</key><dict>'
  while IFS=$'\t' read -r key value; do
    [[ -n "$key" ]] || continue
    case "$value" in
      true|false) printf '                <key>%s</key><%s/>\n' "$(xml_escape "$key")" "$value" ;;
      *) printf '                <key>%s</key><string>%s</string>\n' "$(xml_escape "$key")" "$(xml_escape "$value")" ;;
    esac
  done <<< "$lines"
  printf '%s\n' '              </dict></dict></dict></dict></dict>'
}

domain_preference_lines() {
  local domain="$1" feature pref_domain key value lines=''
  for feature in "${FEATURES[@]}"; do
    kept "$feature" && continue
    while IFS=$'\t' read -r pref_domain key value; do
      [[ "$pref_domain" == "$domain" ]] || continue
      lines="${lines}${key}"$'\t'"${value}"$'\n'
    done < <(feature_preferences "$feature")
  done
  printf '%s' "$lines"
}

restriction_lines() {
  local feature key lines=''
  for feature in "${FEATURES[@]}"; do
    kept "$feature" && continue
    while IFS= read -r key; do
      [[ -n "$key" ]] && lines="${lines}${key}"$'\n'
    done < <(feature_restrictions "$feature")
  done
  printf '%s' "$lines"
}

download_lines() {
  local set key lines=''
  while IFS= read -r set; do
    [[ -n "$set" ]] || continue
    key="DownloadServerBaseURLOverride-$(model_set_asset_type "$set")"
    lines="${lines}${key}"$'\t'"${BLOCKED_URL}"$'\n'
  done < <(sets_to_remove)
  printf '%s' "$lines"
}

build_profile() {
  local output="$1" sets="$2" tmp="$output.tmp.$$" domain lines key
  local restrictions="$(restriction_lines)"
  local assets="$(download_lines)"
  mkdir -p "$(dirname "$output")"
  {
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
    printf '%s\n' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList 1.0//EN">'
    printf '%s\n' '<plist version="1.0"><dict>'
    printf '%s\n' '<key>PayloadType</key><string>Configuration</string>'
    printf '%s\n' '<key>PayloadVersion</key><integer>1</integer>'
    printf '<key>PayloadIdentifier</key><string>%s</string>\n' "$PROFILE_ID"
    printf '<key>PayloadUUID</key><string>%s</string>\n' "$(stable_uuid "$PROFILE_ID")"
    printf '<key>PayloadDisplayName</key><string>%s</string>\n' "$(xml_escape "$PROFILE_NAME")"
    printf '%s\n' '<key>PayloadDescription</key><string>Disables Apple Intelligence features and blocks selected model downloads. Remove this profile to undo.</string>'
    printf '%s\n' '<key>PayloadOrganization</key><string>Apple AI remover</string>'
    printf '%s\n' '<key>PayloadScope</key><string>System</string>'
    printf '%s\n' '<key>PayloadRemovalDisallowed</key><false/>'
    printf '%s\n' '<key>PayloadContent</key><array>'

    if [[ -n "$restrictions" ]]; then
      payload_header com.apple.applicationaccess restrictions 'Apple Intelligence restrictions'
      printf '%s\n' '      <key>PayloadContent</key><dict>'
      while IFS= read -r key; do
        [[ -n "$key" ]] && printf '        <key>%s</key><false/>\n' "$(xml_escape "$key")"
      done <<< "$restrictions"
      printf '%s\n' '      </dict></dict>'
    fi

    for domain in com.apple.assistant.support com.apple.Siri group.com.apple.mail group.com.apple.usernoted com.apple.MobileSMS .GlobalPreferences com.apple.spatialphotosrelive; do
      lines="$(domain_preference_lines "$domain")"
      emit_preferences_payload "$domain" "$domain" "Forced settings: $domain" "$lines"
    done
    emit_preferences_payload com.apple.MobileAsset MobileAsset 'MobileAsset download overrides' "$assets"

    lines="installed"$'\t'true$'\n'"kept"$'\t'"$(printf '%s' "${KEEP[*]:-}" | tr ' ' ',')"$'\n'
    emit_preferences_payload "$PROFILE_ID" marker 'Apple AI remover state' "$lines"

    printf '%s\n' '</array></dict></plist>'
  } > "$tmp"
  /usr/bin/plutil -lint "$tmp" >/dev/null 2>&1 || { rm -f "$tmp"; fail 'generated profile failed plist validation'; }
  mv "$tmp" "$output"
}

helper_pref() { "$HELPER" pref "$1" "$2"; }
profile_installed() { local output; output="$(helper_pref "$PROFILE_ID" installed 2>/dev/null)" || return 1; [[ "$output" == *$'forced=1\tvalue=true'* ]]; }
legacy_profile_installed() { local output; output="$(helper_pref "$LEGACY_PROFILE_ID" installed 2>/dev/null)" || return 1; [[ "$output" == *$'forced=1\tvalue=true'* ]]; }
upstream_profile_installed() { local output; output="$(helper_pref "$UPSTREAM_PROFILE_ID" installed 2>/dev/null)" || return 1; [[ "$output" == *$'forced=1\tvalue=true'* ]]; }
profile_kept_csv() { local output; output="$(helper_pref "$PROFILE_ID" kept 2>/dev/null)" || return 1; printf '%s' "${output#*value=}"; }

validate_uaf_catalog() {
  local set expected actual
  for set in "${MODEL_SETS[@]}"; do
    expected="$(model_set_asset_type "$set")"
    actual="$($HELPER asset-type "$set")" || fail "UAF lookup failed for $set"
    [[ "$actual" == "$expected" ]] || fail "UAF mapping mismatch for $set: expected $expected, got $actual"
  done
}

model_bytes() {
  local set="$1" output
  output="$($HELPER bytes "$set" 2>/dev/null)" || return 1
  [[ "$output" =~ ^[0-9]+$ ]] || return 1
  printf '%s' "$output"
}

format_bytes() {
  local b="$1"
  if (( b >= 1000000000 )); then awk -v n="$b" 'BEGIN { printf "%.1f GB", n/1e9 }'
  elif (( b > 0 )); then awk -v n="$b" 'BEGIN { printf "%.0f MB", n/1e6 }'
  else echo '0 MB'; fi
}

feature_state() {
  local feature="$1" domain key want output
  local pref_has=0 pref_forced_off=1 pref_values_off=1
  local restriction_has=0 restriction_forced_off=1

  while IFS=$'\t' read -r domain key want; do
    [[ -n "$domain" ]] || continue
    pref_has=1
    output="$(helper_pref "$domain" "$key" 2>/dev/null)" || { echo unknown; return; }
    [[ "$output" == "forced=1"$'\t'"value=$want" ]] || pref_forced_off=0
    [[ "$output" == *$'\t'"value=$want" ]] || pref_values_off=0
  done < <(feature_preferences "$feature")

  while IFS= read -r key; do
    [[ -n "$key" ]] || continue
    restriction_has=1
    output="$(helper_pref com.apple.applicationaccess "$key" 2>/dev/null)" || { echo unknown; return; }
    [[ "$output" == *$'forced=1\tvalue=false'* ]] || restriction_forced_off=0
  done < <(feature_restrictions "$feature")

  if (( pref_has == 1 || restriction_has == 1 )); then
    if (( (pref_has == 0 || pref_forced_off == 1) && (restriction_has == 0 || restriction_forced_off == 1) )); then
      echo locked
    elif (( pref_has == 1 && pref_values_off == 1 )); then
      echo off
    else
      echo on
    fi
    return
  fi

  if profile_installed && ! kept "$feature"; then
    echo locked
    return
  fi

  local set total=0 known=1 n
  while IFS= read -r set; do
    [[ -n "$set" ]] || continue
    if ! n="$(model_bytes "$set")"; then known=0; break; fi
    total=$((total+n))
  done < <(feature_model_sets "$feature")
  if (( known == 0 )); then echo unknown; elif (( total > 0 )); then echo on; else echo off; fi
}

status_command() {
  build_helper
  printf '%s %s · macOS %s\n\n' "$PRODUCT_NAME" "$VERSION" "$(sw_vers -productVersion)"
  local feature set state bytes total=0
  printf 'Features\n'
  for feature in "${FEATURES[@]}"; do
    state="$(feature_state "$feature")"
    printf '  %-42s %s\n' "$(feature_title "$feature")" "$state"
  done
  printf '\nModels on disk\n'
  for set in "${MODEL_SETS[@]}"; do
    if bytes="$(model_bytes "$set")"; then
      total=$((total+bytes))
      printf '  %-42s %s\n' "$(model_set_title "$set")" "$(format_bytes "$bytes")"
    else
      printf '  %-42s unknown\n' "$(model_set_title "$set")"
    fi
  done
  printf '  %-42s %s\n' Total "$(format_bytes "$total")"
  if profile_installed; then printf 'Profile: installed\n'; else printf 'Profile: not-installed\n'; fi
}

print_features() {
  local f
  for f in "${FEATURES[@]}"; do printf '%-28s %s\n' "$f" "$(feature_title "$f")"; done
}

open_profile_settings() {
  open 'x-apple.systempreferences:com.apple.Profiles-Settings.extension' 2>/dev/null ||
    open 'x-apple.systempreferences:com.apple.preferences.configurationprofiles' 2>/dev/null || true
}

wait_for_profile() {
  local expected="$1" seconds=0
  while (( seconds < 600 )); do
    if profile_installed && [[ "$(profile_kept_csv || true)" == "$expected" ]]; then return 0; fi
    sleep 2
    seconds=$((seconds+2))
  done
  return 1
}

reset_models() {
  local set failures=0
  while IFS= read -r set; do
    [[ -n "$set" ]] || continue
    if "$HELPER" reset "$set"; then
      info "reset: $set"
    else
      warn "asset reset failed: $set"
      failures=$((failures+1))
    fi
  done <<< "$1"
  return "$failures"
}

confirm() {
  (( YES == 1 )) && return 0
  [[ -t 0 ]] || fail 'run in a terminal or pass --yes'
  printf 'Turn off Apple Intelligence and reset selected models? [y/N] '
  read -r answer
  [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

off_command() {
  parse_args "$@"
  build_helper
  if legacy_profile_installed || upstream_profile_installed; then
    fail 'another RemoveMacAI profile is installed; remove it before using this implementation'
  fi
  validate_uaf_catalog
  local sets="$(sets_to_remove)" feature expected
  printf 'Features to disable:\n'
  for feature in "${FEATURES[@]}"; do kept "$feature" || printf '  - %s\n' "$(feature_title "$feature")"; done
  printf 'Model sets to reset:\n'
  if [[ -n "$sets" ]]; then printf '%s\n' "$sets" | sed 's/^/  - /'; else printf '  - none\n'; fi

  if (( DRY_RUN == 1 )); then
    local dry="${TMPDIR:-/tmp}/Apple-AI-remover.$$.mobileconfig"
    build_profile "$dry" "$sets"
    info 'DRY RUN: no profile was installed and no model was reset.'
    info "generated profile: $dry"
    return 0
  fi

  confirm || { info 'Nothing changed.'; return 0; }
  expected="$(printf '%s' "${KEEP[*]:-}" | tr ' ' ',')"
  build_profile "$PROFILE_FILE" "$sets"
  open "$PROFILE_FILE" 2>/dev/null || true
  open_profile_settings
  info "Approve '$PROFILE_NAME' in System Settings."
  wait_for_profile "$expected" || fail 'profile installation was not observed; no model reset was attempted'

  if [[ -n "$sets" ]]; then
    reset_models "$sets" || fail 'one or more selected model sets failed to reset; run status to inspect the remaining state'
  fi
  info 'Done. Run: ./remove-mac-ai.sh status'
}

revert_command() {
  build_helper
  local current=0 legacy=0
  profile_installed && current=1
  legacy_profile_installed && legacy=1
  if (( current == 0 && legacy == 0 )); then info 'No Apple AI remover profile is installed.'; return 0; fi
  if (( YES == 0 )); then
    [[ -t 0 ]] || fail 'run in a terminal or pass --yes'
    printf 'Remove Apple AI remover profile(s)? [y/N] '
    read -r answer
    [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]] || { info 'Nothing changed.'; return 0; }
  fi
  (( current == 1 )) && sudo /usr/bin/profiles remove -identifier "$PROFILE_ID"
  (( legacy == 1 )) && sudo /usr/bin/profiles remove -identifier "$LEGACY_PROFILE_ID"
  local seconds=0
  while (( seconds < 120 )); do
    ! profile_installed && ! legacy_profile_installed && { info 'Profile(s) removed.'; return 0; }
    sleep 1
    seconds=$((seconds+1))
  done
  fail 'profile removal was not observed after 120 seconds'
}

selftest_command() {
  need_cmd shasum
  need_cmd plutil
  local feature set all test_keep tmp
  for feature in "${FEATURES[@]}"; do
    feature_title "$feature" >/dev/null || fail "missing title for $feature"
    while IFS= read -r set; do
      [[ -z "$set" ]] || model_set_asset_type "$set" >/dev/null || fail "unknown model set $set"
    done < <(feature_model_sets "$feature")
  done
  for set in "${MODEL_SETS[@]}"; do model_set_asset_type "$set" >/dev/null || fail "missing model-set mapping $set"; done
  KEEP=()
  all="$(sets_to_remove)"
  [[ "$(printf '%s\n' "$all" | sort)" == "$(printf '%s\n' "${MODEL_SETS[@]}" | sort)" ]] || fail 'empty keep set must remove every model set'
  KEEP=(writing-tools)
  all="$(sets_to_remove)"
  grep -qx 'com.apple.modelcatalog' <<< "$all" && fail 'writing-tools must protect foundation models'
  grep -qx 'com.apple.MobileAsset.UAF.FM.Visual' <<< "$all" || fail 'writing-tools must not protect visual models'
  KEEP=()
  test_keep="$(stable_uuid "$PROFILE_ID")"
  [[ "$test_keep" == "$(stable_uuid "$PROFILE_ID")" ]] || fail 'payload UUIDs are not stable'
  tmp="${TMPDIR:-/tmp}/apple-ai-remover-selftest.$$.mobileconfig"
  build_profile "$tmp" "$(sets_to_remove)"
  /usr/bin/plutil -lint "$tmp" >/dev/null 2>&1 || fail 'self-test profile is not valid plist'
  grep -q 'DownloadServerBaseURLOverride-com.apple.MobileAsset.UAF.FM.GenerativeModels' "$tmp" || fail 'self-test profile lacks foundation model download override'
  rm -f "$tmp"
  printf 'selftest: PASS (%s features, %s model sets)\n' "${#FEATURES[@]}" "${#MODEL_SETS[@]}"
}

usage() {
  cat <<EOF
$PRODUCT_NAME $VERSION

Usage:
  $0 status
  $0 features
  $0 off [--keep feature[,feature...]] [--dry-run] [--yes]
  $0 revert [--yes]
  $0 selftest

Mutating commands target macOS $TARGET_MAJOR.x on Apple silicon.
EOF
}

main() {
  local command="${1:-status}"
  shift || true
  case "$command" in
    status) require_platform; status_command "$@" ;;
    features) [[ $# -eq 0 ]] || fail 'features takes no options'; print_features ;;
    off) require_platform; off_command "$@" ;;
    revert) require_platform; parse_args "$@"; revert_command ;;
    selftest) [[ $# -eq 0 ]] || fail 'selftest takes no options'; selftest_command ;;
    --help|-h|help) usage ;;
    --version|-v|version) echo "$VERSION" ;;
    *) usage >&2; exit 1 ;;
  esac
}

main "$@"
