#!/bin/bash
set -euo pipefail

readonly VERSION='0.2.0'
readonly PRODUCT_NAME='Apple AI remover'
readonly PROFILE_ID='io.github.pmorgaonkar.apple-ai-remover'
readonly LEGACY_PROFILE_ID='io.github.omlahore.removemacai.bash'
readonly UPSTREAM_PROFILE_ID='io.github.omlahore.removemacai'
readonly PROFILE_NAME='Apple AI remover'
readonly PROFILE_FILE="$HOME/Downloads/Apple-AI-remover.mobileconfig"
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly HELPER_SOURCE="$SCRIPT_DIR/uaf-reset.m"
readonly BUILD_SCRIPT="$SCRIPT_DIR/build-helper.sh"
readonly BLOCKED_URL='https://127.0.0.1:9/apple-ai-remover-blocked/'
readonly TARGET_MAJOR=27

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

fail() { printf 'error: %s\n' "$*" >&2; exit 1; }
info() { printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"; }

require_platform() {
  [[ "$(uname -s)" == Darwin ]] || fail 'this utility runs on macOS'
  [[ "$(uname -m)" == arm64 ]] || fail 'this build targets Apple silicon (arm64)'
  local version major
  version="$(sw_vers -productVersion)"
  major="${version%%.*}"
  [[ "$major" == "$TARGET_MAJOR" ]] || fail "unsupported macOS $version; this release targets macOS $TARGET_MAJOR.x"
}

cleanup_helper() { [[ -n "$HELPER_DIR" && -d "$HELPER_DIR" ]] && rm -rf "$HELPER_DIR"; }

build_helper() {
  need_cmd clang
  need_cmd mktemp
  [[ -r "$HELPER_SOURCE" ]] || fail "missing native helper source: $HELPER_SOURCE"
  [[ -x "$BUILD_SCRIPT" ]] || fail "missing executable build script: $BUILD_SCRIPT"
  if [[ -n "$HELPER" && -x "$HELPER" ]]; then return; fi
  HELPER_DIR="$(mktemp -d "${TMPDIR:-/tmp}/apple-ai-remover.XXXXXX")"
  HELPER="$HELPER_DIR/uaf-reset"
  trap cleanup_helper EXIT HUP INT TERM
  "$BUILD_SCRIPT" "$HELPER" >/dev/null || fail 'native helper build failed'
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
    com.apple.modelcatalog) echo 'com.apple.MobileAsset.UAF.FM.GenerativeModels' ;;
    com.apple.MobileAsset.UAF.FM.Visual) echo 'com.apple.MobileAsset.UAF.FM.Visual' ;;
    com.apple.MobileAsset.UAF.Photos.SpatialPhotosRelive) echo 'com.apple.MobileAsset.UAF.Photos.SpatialPhotosRelive' ;;
    com.apple.MobileAsset.UAF.Photos.MagicCleanup) echo 'com.apple.MobileAsset.UAF.Photos.MagicCleanup' ;;
    com.apple.MobileAsset.UAF.FM.CodeLM) echo 'com.apple.MobileAsset.UAF.FM.CodeLM' ;;
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

add_keep() {
  feature_exists "$1" || fail "unknown feature '$1'"
  kept "$1" || KEEP=("${KEEP[@]}" "$1")
}

parse_keep_value() {
  local raw="$1" old_ifs="$IFS" item
  IFS=','
  read -r -a _items <<< "$raw"
  IFS="$old_ifs"
  for item in "${_items[@]}"; do
    item="$(printf '%s' "$item" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -n "$item" ]] && add_keep "$item"
  done
}

parse_args() {
  KEEP=()
  DRY_RUN=0
  YES=0
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --keep)
        [[ "$#" -ge 2 ]] || fail '--keep requires a feature name or comma-separated list'
        parse_keep_value "$2"; shift 2 ;;
      --dry-run) DRY_RUN=1; shift ;;
      --yes|-y) YES=1; shift ;;
      *) fail "unknown option '$1'" ;;
    esac
  done
}

model_set_users() {
  local target="$1" feature
  for feature in "${FEATURES[@]}"; do
    while IFS= read -r set; do
      [[ "$set" == "$target" ]] && printf '%s\n' "$feature"
    done < <(feature_model_sets "$feature")
  done
}

model_set_should_remove() {
  local target="$1" user
  while IFS= read -r user; do
    kept "$user" && return 1
  done < <(model_set_users "$target")
  return 0
}

sets_to_remove() {
  local set
  for set in "${MODEL_SETS[@]}"; do
    model_set_should_remove "$set" && printf '%s\n' "$set"
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
  local name="$1" h variant_byte
  h="$(printf '%s' "$name" | shasum -a 1 | awk '{print $1}')"
  variant_byte=$((16#${h:16:2} & 63 | 128))
  printf '%s-%s-%s-%s-%s\n' "${h:0:8}" "${h:8:4}" "5${h:13:3}" "$(printf '%02x' "$variant_byte")${h:18:2}" "${h:20:12}"
}

payload_header() {
  local type="$1" suffix="$2" name="$3" id="$PROFILE_ID.$suffix"
  cat <<EOF_PAYLOAD
    <dict>
      <key>PayloadType</key><string>$(xml_escape "$type")</string>
      <key>PayloadVersion</key><integer>1</integer>
      <key>PayloadIdentifier</key><string>$(xml_escape "$id")</string>
      <key>PayloadUUID</key><string>$(stable_uuid "$id")</string>
      <key>PayloadDisplayName</key><string>$(xml_escape "$name")</string>
EOF_PAYLOAD
}

append_pref_payload() {
  local domain="$1" suffix="$2" title="$3"
  [[ -n "$PREF_LINES" ]] || return 0
  payload_header com.apple.ManagedClient.preferences "preferences.$suffix" "$title"
  printf '%s\n' '      <key>PayloadContent</key>' '      <dict>'
  printf '        <key>%s</key>\n' "$(xml_escape "$domain")"
  printf '%s\n' '        <dict>' '          <key>Forced</key>' '          <array>' '            <dict>' '              <key>mcx_preference_settings</key>' '              <dict>'
  while IFS=$'\t' read -r key value; do
    [[ -n "$key" ]] || continue
    if [[ "$value" == true || "$value" == false ]]; then
      printf '                <key>%s</key><%s/>\n' "$(xml_escape "$key")" "$value"
    else
      printf '                <key>%s</key><string>%s</string>\n' "$(xml_escape "$key")" "$(xml_escape "$value")"
    fi
  done <<< "$PREF_LINES"
  printf '%s\n' '              </dict>' '            </dict>' '          </array>' '        </dict>' '      </dict>' '    </dict>'
}

build_profile() {
  local output="$1" sets="$2" tmp="$output.tmp.$$"
  local feature domain key value set d
  ALL_PREFS=''
  for feature in "${FEATURES[@]}"; do
    kept "$feature" && continue
    while IFS=$'\t' read -r domain key value; do
      [[ -n "$domain" ]] || continue
      ALL_PREFS="${ALL_PREFS}${domain}"
    [[ -n "$set" ]] || continue
    key="DownloadServerBaseURLOverride-$(model_set_asset_type "$set")"
    PREF_LINES="${PREF_LINES}com.apple.MobileAsset"$'\t'"${key}"$'\t'"${BLOCKED_URL}"$'\n'
  done <<< "$sets"

  mkdir -p "$(dirname "$output")"
  {
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
    printf '%s\n' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    printf '%s\n' '<plist version="1.0"><dict>'
    printf '%s\n' '<key>PayloadType</key><string>Configuration</string>'
    printf '%s\n' '<key>PayloadVersion</key><integer>1</integer>'
    printf '<key>PayloadIdentifier</key><string>%s</string>\n' "$PROFILE_ID"
    printf '<key>PayloadUUID</key><string>%s</string>\n' "$(stable_uuid "$PROFILE_ID")"
    printf '<key>PayloadDisplayName</key><string>%s</string>\n' "$(xml_escape "$PROFILE_NAME")"
    printf '%s\n' '<key>PayloadDescription</key><string>Disables Apple Intelligence features and prevents selected model sets from being re-downloaded. Remove this profile to undo.</string>'
    printf '%s\n' '<key>PayloadOrganization</key><string>Apple AI remover</string>'
    printf '%s\n' '<key>PayloadScope</key><string>System</string>'
    printf '%s\n' '<key>PayloadRemovalDisallowed</key><false/>'
    printf '%s\n' '<key>PayloadContent</key><array>'

    payload_header com.apple.applicationaccess restrictions 'Apple Intelligence restrictions'
    printf '%s\n' '      <key>PayloadContent</key><dict>'
    for feature in "${FEATURES[@]}"; do
      kept "$feature" && continue
      while IFS= read -r key; do
        [[ -n "$key" ]] && printf '        <key>%s</key><false/>\n' "$(xml_escape "$key")"
      done < <(feature_restrictions "$feature")
    done
    printf '%s\n' '      </dict>' '    </dict>'

    for d in com.apple.assistant.support com.apple.Siri group.com.apple.mail group.com.apple.usernoted com.apple.MobileSMS .GlobalPreferences com.apple.spatialphotosrelive; do
      PREF_LINES=''
      while IFS=$'\t' read -r domain key value; do
        [[ "$domain" == "$d" ]] || continue
        PREF_LINES="${PREF_LINES}${key}"$'\t'"${value}"$'\n'
      done <<< "$ALL_PREFS"
      append_pref_payload "$d" "$d" "Forced settings: $d"
    done

    PREF_LINES=''
    while IFS=$'\t' read -r domain key value; do
      [[ "$domain" == 'com.apple.MobileAsset' ]] || continue
      PREF_LINES="${PREF_LINES}${key}"$'\t'"${value}"$'\n'
    done <<< "$ALL_PREFS"
    append_pref_payload com.apple.MobileAsset MobileAsset 'MobileAsset download overrides'

    PREF_LINES="installed"$'\t'true$'\n'"kept"$'\t'"$(keep_csv)"$'\n'
    append_pref_payload "$PROFILE_ID" marker 'Apple AI remover state'

    printf '%s\n' '</array></dict></plist>'
  } > "$tmp"
  /usr/bin/plutil -lint "$tmp" >/dev/null 2>&1 || { rm -f "$tmp"; fail 'generated profile failed plist validation'; }
  mv "$tmp" "$output"
}

keep_csv() {
  local out='' item
  for item in "${KEEP[@]}"; do
    [[ -n "$out" ]] && out="$out,"
    out="$out$item"
  done
  printf '%s' "$out"
}

helper_pref() { "$HELPER" pref "$1" "$2"; }
profile_installed() {
  local output
  output="$(helper_pref "$PROFILE_ID" installed 2>/dev/null)" || return 1
  [[ "$output" == *$'forced=1\tvalue=true'* ]]
}
legacy_profile_installed() {
  local output
  output="$(helper_pref "$LEGACY_PROFILE_ID" installed 2>/dev/null)" || return 1
  [[ "$output" == *$'forced=1\tvalue=true'* ]]
}
upstream_profile_installed() {
  local output
  output="$(helper_pref "$UPSTREAM_PROFILE_ID" installed 2>/dev/null)" || return 1
  [[ "$output" == *$'forced=1\tvalue=true'* ]]
}
profile_kept_csv() {
  local output
  output="$(helper_pref "$PROFILE_ID" kept 2>/dev/null)" || return 1
  printf '%s' "${output#*value=}"
}

validate_uaf_catalog() {
  local set expected actual
  for set in "${MODEL_SETS[@]}"; do
    expected="$(model_set_asset_type "$set")"
    actual="$($HELPER asset-type "$set")" || fail "UAF asset-set lookup failed for $set"
    [[ "$actual" == "$expected" ]] || fail "UAF mapping mismatch for $set: expected $expected, got $actual"
  done
}

model_bytes() {
  local set="$1" out
  out="$($HELPER bytes "$set" 2>/dev/null)" || return 1
  [[ "$out" =~ ^[0-9]+$ ]] || return 1
  printf '%s' "$out"
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
  if (( known == 0 )); then
    echo unknown
  elif (( total > 0 )); then
    echo on
  else
    echo off
  fi
}

status_command() {
  build_helper
  printf '%s %s · macOS %s\n\n' "$PRODUCT_NAME" "$VERSION" "$(sw_vers -productVersion)"
  local feature state set n total=0
  for feature in "${FEATURES[@]}"; do
    state="$(feature_state "$feature")"
    printf '%-44s %s\n' "$(feature_title "$feature")" "$state"
  done
  printf '\nModels on disk\n'
  for set in "${MODEL_SETS[@]}"; do
    if n="$(model_bytes "$set")"; then
      total=$((total+n)); printf '  %-44s %s\n' "$(model_set_title "$set")" "$(format_bytes "$n")"
    else
      printf '  %-44s unknown\n' "$(model_set_title "$set")"
    fi
  done
  printf '  %-44s %s\n' Total "$(format_bytes "$total")"
  printf 'Profile: %s\n' "$(profile_installed && echo installed || echo not-installed)"
}

print_features() {
  local f
  for f in "${FEATURES[@]}"; do printf '%-28s %s\n' "$f" "$(feature_title "$f")"; done
}

open_profile_settings() {
  open 'x-apple.systempreferences:com.apple.Profiles-Settings.extension' 2>/dev/null || open 'x-apple.systempreferences:com.apple.preferences.configurationprofiles' 2>/dev/null || true
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
  printf 'Turn off Apple Intelligence and reset the selected models? [y/N] '
  read -r answer
  [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

off_command() {
  parse_args "$@"
  build_helper
  if legacy_profile_installed || upstream_profile_installed; then
    fail "another RemoveMacAI configuration profile is installed; remove it before using this implementation"
  fi
  validate_uaf_catalog
  local sets
  sets="$(sets_to_remove)"

  printf 'Features to disable:\n'
  local f
  for f in "${FEATURES[@]}"; do kept "$f" || printf '  - %s\n' "$(feature_title "$f")"; done
  printf 'Model sets to reset:\n%s\n' "$(printf '%s\n' "$sets" | sed 's/^/  - /')"

  if (( DRY_RUN == 1 )); then
    local dry="${TMPDIR:-/tmp}/Apple-AI-remover.$$.mobileconfig"
    build_profile "$dry" "$sets"
    info 'DRY RUN: no profile was installed and no model was reset.'
    info "generated profile: $dry"
    return 0
  fi

  confirm || { info 'Nothing changed.'; return 0; }

  local expected
  expected="$(keep_csv)"
  build_profile "$PROFILE_FILE" "$sets"
  open "$PROFILE_FILE" 2>/dev/null || true
  open_profile_settings
  info "Approve '$PROFILE_NAME' in System Settings."
  wait_for_profile "$expected" || fail 'profile installation was not observed; no model reset was attempted'

  if [[ -n "$sets" ]]; then
    if reset_models "$sets"; then
      info 'All selected model sets reset successfully.'
    else
      fail 'profile is installed, but one or more model resets failed; run status to inspect remaining model state'
    fi
  fi
  info "Done. Run: $0 status"
}

revert_command() {
  build_helper
  local current=0 legacy=0
  profile_installed && current=1
  legacy_profile_installed && legacy=1
  if (( current == 0 && legacy == 0 )); then info 'No Apple AI remover profile is installed.'; return 0; fi
  if (( YES == 0 )); then
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
  local f set x saved_keep all a b
  for f in "${FEATURES[@]}"; do
    feature_title "$f" >/dev/null || fail "missing title for $f"
    while IFS= read -r x; do
      [[ -z "$x" ]] && continue
      model_set_asset_type "$x" >/dev/null || fail "unknown model set $x referenced by $f"
    done < <(feature_model_sets "$f")
  done
  for set in "${MODEL_SETS[@]}"; do model_set_asset_type "$set" >/dev/null || fail "missing model-set mapping $set"; done

  saved_keep=("${KEEP[@]}")
  KEEP=()
  all="$(sets_to_remove)"
  [[ "$(printf '%s\n' "$all" | sort)" == "$(printf '%s\n' "${MODEL_SETS[@]}" | sort)" ]] || fail 'empty keep set must remove every model set'

  KEEP=(writing-tools)
  all="$(sets_to_remove)"
  ! grep -qx 'com.apple.modelcatalog' <<< "$all" || fail 'writing-tools must protect foundation models'
  grep -qx 'com.apple.MobileAsset.UAF.FM.Visual' <<< "$all" || fail 'writing-tools unexpectedly protects visual models'
  KEEP=("${saved_keep[@]}")

  a="$(stable_uuid "$PROFILE_ID")"; b="$(stable_uuid "$PROFILE_ID")"; [[ "$a" == "$b" ]] || fail 'payload UUID generator is not stable'
  printf 'selftest: PASS (%s features, %s model sets)\n' "${#FEATURES[@]}" "${#MODEL_SETS[@]}"
}

usage() {
  cat <<EOF_USAGE
$PRODUCT_NAME $VERSION

Usage:
  $0 status
  $0 features
  $0 off [--keep feature[,feature...]] [--dry-run] [--yes]
  $0 revert [--yes]
  $0 selftest

The mutating commands target macOS $TARGET_MAJOR.x on Apple silicon.
EOF_USAGE
}

main() {
  local command="${1:-status}"
  shift || true
  case "$command" in
    status) require_platform; status_command "$@" ;;
    features) [[ "$#" -eq 0 ]] || fail 'features takes no options'; print_features ;;
    off) require_platform; off_command "$@" ;;
    revert) require_platform; parse_args "$@"; revert_command ;;
    selftest) [[ "$#" -eq 0 ]] || fail 'selftest takes no options'; selftest_command ;;
    --help|-h|help) usage ;;
    --version|-v|version) echo "$VERSION" ;;
    *) usage >&2; exit 1 ;;
  esac
}

main "$@"
\t'"${key}"
    [[ -n "$set" ]] || continue
    key="DownloadServerBaseURLOverride-$(model_set_asset_type "$set")"
    PREF_LINES="${PREF_LINES}com.apple.MobileAsset"$'\t'"${key}"$'\t'"${BLOCKED_URL}"$'\n'
  done <<< "$sets"

  mkdir -p "$(dirname "$output")"
  {
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
    printf '%s\n' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    printf '%s\n' '<plist version="1.0"><dict>'
    printf '%s\n' '<key>PayloadType</key><string>Configuration</string>'
    printf '%s\n' '<key>PayloadVersion</key><integer>1</integer>'
    printf '<key>PayloadIdentifier</key><string>%s</string>\n' "$PROFILE_ID"
    printf '<key>PayloadUUID</key><string>%s</string>\n' "$(stable_uuid "$PROFILE_ID")"
    printf '<key>PayloadDisplayName</key><string>%s</string>\n' "$(xml_escape "$PROFILE_NAME")"
    printf '%s\n' '<key>PayloadDescription</key><string>Disables Apple Intelligence features and prevents selected model sets from being re-downloaded. Remove this profile to undo.</string>'
    printf '%s\n' '<key>PayloadOrganization</key><string>Apple AI remover</string>'
    printf '%s\n' '<key>PayloadScope</key><string>System</string>'
    printf '%s\n' '<key>PayloadRemovalDisallowed</key><false/>'
    printf '%s\n' '<key>PayloadContent</key><array>'

    payload_header com.apple.applicationaccess restrictions 'Apple Intelligence restrictions'
    printf '%s\n' '      <key>PayloadContent</key><dict>'
    for feature in "${FEATURES[@]}"; do
      kept "$feature" && continue
      while IFS= read -r key; do
        [[ -n "$key" ]] && printf '        <key>%s</key><false/>\n' "$(xml_escape "$key")"
      done < <(feature_restrictions "$feature")
    done
    printf '%s\n' '      </dict>' '    </dict>'

    for d in com.apple.assistant.support com.apple.Siri group.com.apple.mail group.com.apple.usernoted com.apple.MobileSMS .GlobalPreferences com.apple.spatialphotosrelive; do
      PREF_LINES=''
      while IFS=$'\t' read -r domain key value; do
        [[ "$domain" == "$d" ]] || continue
        PREF_LINES="${PREF_LINES}${key}"$'\t'"${value}"$'\n'
      done <<< "$ALL_PREFS"
      append_pref_payload "$d" "$d" "Forced settings: $d"
    done

    PREF_LINES=''
    while IFS=$'\t' read -r domain key value; do
      [[ "$domain" == 'com.apple.MobileAsset' ]] || continue
      PREF_LINES="${PREF_LINES}${key}"$'\t'"${value}"$'\n'
    done <<< "$ALL_PREFS"
    append_pref_payload com.apple.MobileAsset MobileAsset 'MobileAsset download overrides'

    PREF_LINES="installed"$'\t'true$'\n'"kept"$'\t'"$(keep_csv)"$'\n'
    append_pref_payload "$PROFILE_ID" marker 'Apple AI remover state'

    printf '%s\n' '</array></dict></plist>'
  } > "$tmp"
  /usr/bin/plutil -lint "$tmp" >/dev/null 2>&1 || { rm -f "$tmp"; fail 'generated profile failed plist validation'; }
  mv "$tmp" "$output"
}

keep_csv() {
  local out='' item
  for item in "${KEEP[@]}"; do
    [[ -n "$out" ]] && out="$out,"
    out="$out$item"
  done
  printf '%s' "$out"
}

helper_pref() { "$HELPER" pref "$1" "$2"; }
profile_installed() { local o; o="$(helper_pref "$PROFILE_ID" installed 2>/dev/null)" || return 1; [[ "$o" == *$'forced=1\tvalue=true'* ]]; }
legacy_profile_installed() { local o; o="$(helper_pref "$LEGACY_PROFILE_ID" installed 2>/dev/null)" || return 1; [[ "$o" == *
validate_uaf_catalog() {
  local set expected actual
  for set in "${MODEL_SETS[@]}"; do
    expected="$(model_set_asset_type "$set")"
    actual="$($HELPER asset-type "$set")" || fail "UAF asset-set lookup failed for $set"
    [[ "$actual" == "$expected" ]] || fail "UAF mapping mismatch for $set: expected $expected, got $actual"
  done
}

model_bytes() {
  local set="$1" out
  out="$($HELPER bytes "$set" 2>/dev/null)" || return 1
  [[ "$out" =~ ^[0-9]+$ ]] || return 1
  printf '%s' "$out"
}

format_bytes() {
  local b="$1"
  if (( b >= 1000000000 )); then awk -v n="$b" 'BEGIN { printf "%.1f GB", n/1e9 }'
  elif (( b > 0 )); then awk -v n="$b" 'BEGIN { printf "%.0f MB", n/1e6 }'
  else echo '0 MB'; fi
}

feature_state() {
  local feature="$1" domain key want output forced value
  local all=1 any=0
  while IFS=$'\t' read -r domain key want; do
    [[ -n "$domain" ]] || continue
    output="$(helper_pref "$domain" "$key" 2>/dev/null)" || { echo unknown; return; }
    forced="$(printf '%s' "$output" | sed -n 's/.*forced=\([^\t]*\).*/\1/p')"
    value="$(printf '%s' "$output" | sed -n 's/.*value=\([^\t]*\)$/\1/p')"
    [[ "$forced" == 1 && "$value" == "$want" ]] && any=1 || all=0
  done < <(feature_preferences "$feature")
  if (( all == 1 && any == 1 )); then echo locked; return; fi

  case "$feature" in
    chatgpt|writing-tools|genmoji|image-playground|safari-summaries|notes-summaries)
      local restricted_ok=1 r
      while IFS= read -r r; do
        [[ -n "$r" ]] || continue
        output="$(helper_pref com.apple.applicationaccess "$r" 2>/dev/null)" || { echo unknown; return; }
        [[ "$output" == *$'forced=1\tvalue=false'* ]] || restricted_ok=0
      done < <(feature_restrictions "$feature")
      (( restricted_ok == 1 )) && echo locked && return
      ;;
  esac

  if profile_installed && ! kept "$feature" && [[ -z "$(feature_preferences "$feature")" ]] && [[ -z "$(feature_restrictions "$feature")" ]]; then
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
  local feature state set n total=0
  for feature in "${FEATURES[@]}"; do
    state="$(feature_state "$feature")"
    printf '%-44s %s\n' "$(feature_title "$feature")" "$state"
  done
  printf '\nModels on disk\n'
  for set in "${MODEL_SETS[@]}"; do
    if n="$(model_bytes "$set")"; then
      total=$((total+n)); printf '  %-44s %s\n' "$(model_set_title "$set")" "$(format_bytes "$n")"
    else
      printf '  %-44s unknown\n' "$(model_set_title "$set")"
    fi
  done
  printf '  %-44s %s\n' Total "$(format_bytes "$total")"
  printf 'Profile: %s\n' "$(profile_installed && echo installed || echo not-installed)"
}

print_features() {
  local f
  for f in "${FEATURES[@]}"; do printf '%-28s %s\n' "$f" "$(feature_title "$f")"; done
}

open_profile_settings() {
  open 'x-apple.systempreferences:com.apple.Profiles-Settings.extension' 2>/dev/null || open 'x-apple.systempreferences:com.apple.preferences.configurationprofiles' 2>/dev/null || true
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
  printf 'Turn off Apple Intelligence and reset the selected models? [y/N] '
  read -r answer
  [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

off_command() {
  parse_args "$@"
  build_helper
  legacy_profile_installed && fail "legacy RemoveMacAI profile is installed; run '$0 revert' first"
  validate_uaf_catalog
  local sets
  sets="$(sets_to_remove)"

  printf 'Features to disable:\n'
  local f
  for f in "${FEATURES[@]}"; do kept "$f" || printf '  - %s\n' "$(feature_title "$f")"; done
  printf 'Model sets to reset:\n%s\n' "$(printf '%s\n' "$sets" | sed 's/^/  - /')"

  if (( DRY_RUN == 1 )); then
    local dry="${TMPDIR:-/tmp}/Apple-AI-remover.$$.mobileconfig"
    build_profile "$dry" "$sets"
    info 'DRY RUN: no profile was installed and no model was reset.'
    info "generated profile: $dry"
    return 0
  fi

  confirm || { info 'Nothing changed.'; return 0; }

  local expected
  expected="$(keep_csv)"
  build_profile "$PROFILE_FILE" "$sets"
  open "$PROFILE_FILE" 2>/dev/null || true
  open_profile_settings
  info "Approve '$PROFILE_NAME' in System Settings."
  wait_for_profile "$expected" || fail 'profile installation was not observed; no model reset was attempted'

  if [[ -n "$sets" ]]; then
    if reset_models "$sets"; then
      info 'All selected model sets reset successfully.'
    else
      fail 'profile is installed, but one or more model resets failed; run status to inspect remaining model state'
    fi
  fi
  info "Done. Run: $0 status"
}

revert_command() {
  build_helper
  local current=0 legacy=0
  profile_installed && current=1
  legacy_profile_installed && legacy=1
  if (( current == 0 && legacy == 0 )); then info 'No Apple AI remover profile is installed.'; return 0; fi
  if (( YES == 0 )); then
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
  local f set x saved_keep all a b
  for f in "${FEATURES[@]}"; do
    feature_title "$f" >/dev/null || fail "missing title for $f"
    while IFS= read -r x; do
      [[ -z "$x" ]] && continue
      model_set_asset_type "$x" >/dev/null || fail "unknown model set $x referenced by $f"
    done < <(feature_model_sets "$f")
  done
  for set in "${MODEL_SETS[@]}"; do model_set_asset_type "$set" >/dev/null || fail "missing model-set mapping $set"; done

  saved_keep=("${KEEP[@]}")
  KEEP=()
  all="$(sets_to_remove)"
  [[ "$(printf '%s\n' "$all" | sort)" == "$(printf '%s\n' "${MODEL_SETS[@]}" | sort)" ]] || fail 'empty keep set must remove every model set'

  KEEP=(writing-tools)
  all="$(sets_to_remove)"
  ! grep -qx 'com.apple.modelcatalog' <<< "$all" || fail 'writing-tools must protect foundation models'
  grep -qx 'com.apple.MobileAsset.UAF.FM.Visual' <<< "$all" || fail 'writing-tools unexpectedly protects visual models'
  KEEP=("${saved_keep[@]}")

  a="$(stable_uuid "$PROFILE_ID")"; b="$(stable_uuid "$PROFILE_ID")"; [[ "$a" == "$b" ]] || fail 'payload UUID generator is not stable'
  printf 'selftest: PASS (%s features, %s model sets)\n' "${#FEATURES[@]}" "${#MODEL_SETS[@]}"
}

usage() {
  cat <<EOF_USAGE
$PRODUCT_NAME $VERSION

Usage:
  $0 status
  $0 features
  $0 off [--keep feature[,feature...]] [--dry-run] [--yes]
  $0 revert [--yes]
  $0 selftest

The mutating commands target macOS $TARGET_MAJOR.x on Apple silicon.
EOF_USAGE
}

main() {
  local command="${1:-status}"
  shift || true
  case "$command" in
    status) require_platform; status_command "$@" ;;
    features) [[ "$#" -eq 0 ]] || fail 'features takes no options'; print_features ;;
    off) require_platform; off_command "$@" ;;
    revert) require_platform; parse_args "$@"; revert_command ;;
    selftest) [[ "$#" -eq 0 ]] || fail 'selftest takes no options'; selftest_command ;;
    --help|-h|help) usage ;;
    --version|-v|version) echo "$VERSION" ;;
    *) usage >&2; exit 1 ;;
  esac
}

main "$@"
\t'"${value}"
    [[ -n "$set" ]] || continue
    key="DownloadServerBaseURLOverride-$(model_set_asset_type "$set")"
    PREF_LINES="${PREF_LINES}com.apple.MobileAsset"$'\t'"${key}"$'\t'"${BLOCKED_URL}"$'\n'
  done <<< "$sets"

  mkdir -p "$(dirname "$output")"
  {
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
    printf '%s\n' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    printf '%s\n' '<plist version="1.0"><dict>'
    printf '%s\n' '<key>PayloadType</key><string>Configuration</string>'
    printf '%s\n' '<key>PayloadVersion</key><integer>1</integer>'
    printf '<key>PayloadIdentifier</key><string>%s</string>\n' "$PROFILE_ID"
    printf '<key>PayloadUUID</key><string>%s</string>\n' "$(stable_uuid "$PROFILE_ID")"
    printf '<key>PayloadDisplayName</key><string>%s</string>\n' "$(xml_escape "$PROFILE_NAME")"
    printf '%s\n' '<key>PayloadDescription</key><string>Disables Apple Intelligence features and prevents selected model sets from being re-downloaded. Remove this profile to undo.</string>'
    printf '%s\n' '<key>PayloadOrganization</key><string>Apple AI remover</string>'
    printf '%s\n' '<key>PayloadScope</key><string>System</string>'
    printf '%s\n' '<key>PayloadRemovalDisallowed</key><false/>'
    printf '%s\n' '<key>PayloadContent</key><array>'

    payload_header com.apple.applicationaccess restrictions 'Apple Intelligence restrictions'
    printf '%s\n' '      <key>PayloadContent</key><dict>'
    for feature in "${FEATURES[@]}"; do
      kept "$feature" && continue
      while IFS= read -r key; do
        [[ -n "$key" ]] && printf '        <key>%s</key><false/>\n' "$(xml_escape "$key")"
      done < <(feature_restrictions "$feature")
    done
    printf '%s\n' '      </dict>' '    </dict>'

    for d in com.apple.assistant.support com.apple.Siri group.com.apple.mail group.com.apple.usernoted com.apple.MobileSMS .GlobalPreferences com.apple.spatialphotosrelive; do
      PREF_LINES=''
      while IFS=$'\t' read -r domain key value; do
        [[ "$domain" == "$d" ]] || continue
        PREF_LINES="${PREF_LINES}${key}"$'\t'"${value}"$'\n'
      done <<< "$ALL_PREFS"
      append_pref_payload "$d" "$d" "Forced settings: $d"
    done

    PREF_LINES=''
    while IFS=$'\t' read -r domain key value; do
      [[ "$domain" == 'com.apple.MobileAsset' ]] || continue
      PREF_LINES="${PREF_LINES}${key}"$'\t'"${value}"$'\n'
    done <<< "$ALL_PREFS"
    append_pref_payload com.apple.MobileAsset MobileAsset 'MobileAsset download overrides'

    PREF_LINES="installed"$'\t'true$'\n'"kept"$'\t'"$(keep_csv)"$'\n'
    append_pref_payload "$PROFILE_ID" marker 'Apple AI remover state'

    printf '%s\n' '</array></dict></plist>'
  } > "$tmp"
  /usr/bin/plutil -lint "$tmp" >/dev/null 2>&1 || { rm -f "$tmp"; fail 'generated profile failed plist validation'; }
  mv "$tmp" "$output"
}

keep_csv() {
  local out='' item
  for item in "${KEEP[@]}"; do
    [[ -n "$out" ]] && out="$out,"
    out="$out$item"
  done
  printf '%s' "$out"
}

helper_pref() { "$HELPER" pref "$1" "$2"; }
profile_installed() { local o; o="$(helper_pref "$PROFILE_ID" installed 2>/dev/null)" || return 1; [[ "$o" == *$'forced=1\tvalue=true'* ]]; }
legacy_profile_installed() { local o; o="$(helper_pref "$LEGACY_PROFILE_ID" installed 2>/dev/null)" || return 1; [[ "$o" == *$'forced=1\tvalue=true'* ]]; }
profile_kept_csv() { local o; o="$(helper_pref "$PROFILE_ID" kept 2>/dev/null)" || return 1; printf '%s' "${o#*value=}"; }

validate_uaf_catalog() {
  local set expected actual
  for set in "${MODEL_SETS[@]}"; do
    expected="$(model_set_asset_type "$set")"
    actual="$($HELPER asset-type "$set")" || fail "UAF asset-set lookup failed for $set"
    [[ "$actual" == "$expected" ]] || fail "UAF mapping mismatch for $set: expected $expected, got $actual"
  done
}

model_bytes() {
  local set="$1" out
  out="$($HELPER bytes "$set" 2>/dev/null)" || return 1
  [[ "$out" =~ ^[0-9]+$ ]] || return 1
  printf '%s' "$out"
}

format_bytes() {
  local b="$1"
  if (( b >= 1000000000 )); then awk -v n="$b" 'BEGIN { printf "%.1f GB", n/1e9 }'
  elif (( b > 0 )); then awk -v n="$b" 'BEGIN { printf "%.0f MB", n/1e6 }'
  else echo '0 MB'; fi
}

feature_state() {
  local feature="$1" domain key want output forced value
  local all=1 any=0
  while IFS=$'\t' read -r domain key want; do
    [[ -n "$domain" ]] || continue
    output="$(helper_pref "$domain" "$key" 2>/dev/null)" || { echo unknown; return; }
    forced="$(printf '%s' "$output" | sed -n 's/.*forced=\([^\t]*\).*/\1/p')"
    value="$(printf '%s' "$output" | sed -n 's/.*value=\([^\t]*\)$/\1/p')"
    [[ "$forced" == 1 && "$value" == "$want" ]] && any=1 || all=0
  done < <(feature_preferences "$feature")
  if (( all == 1 && any == 1 )); then echo locked; return; fi

  case "$feature" in
    chatgpt|writing-tools|genmoji|image-playground|safari-summaries|notes-summaries)
      local restricted_ok=1 r
      while IFS= read -r r; do
        [[ -n "$r" ]] || continue
        output="$(helper_pref com.apple.applicationaccess "$r" 2>/dev/null)" || { echo unknown; return; }
        [[ "$output" == *$'forced=1\tvalue=false'* ]] || restricted_ok=0
      done < <(feature_restrictions "$feature")
      (( restricted_ok == 1 )) && echo locked && return
      ;;
  esac

  if profile_installed && ! kept "$feature" && [[ -z "$(feature_preferences "$feature")" ]] && [[ -z "$(feature_restrictions "$feature")" ]]; then
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
  local feature state set n total=0
  for feature in "${FEATURES[@]}"; do
    state="$(feature_state "$feature")"
    printf '%-44s %s\n' "$(feature_title "$feature")" "$state"
  done
  printf '\nModels on disk\n'
  for set in "${MODEL_SETS[@]}"; do
    if n="$(model_bytes "$set")"; then
      total=$((total+n)); printf '  %-44s %s\n' "$(model_set_title "$set")" "$(format_bytes "$n")"
    else
      printf '  %-44s unknown\n' "$(model_set_title "$set")"
    fi
  done
  printf '  %-44s %s\n' Total "$(format_bytes "$total")"
  printf 'Profile: %s\n' "$(profile_installed && echo installed || echo not-installed)"
}

print_features() {
  local f
  for f in "${FEATURES[@]}"; do printf '%-28s %s\n' "$f" "$(feature_title "$f")"; done
}

open_profile_settings() {
  open 'x-apple.systempreferences:com.apple.Profiles-Settings.extension' 2>/dev/null || open 'x-apple.systempreferences:com.apple.preferences.configurationprofiles' 2>/dev/null || true
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
  printf 'Turn off Apple Intelligence and reset the selected models? [y/N] '
  read -r answer
  [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

off_command() {
  parse_args "$@"
  build_helper
  legacy_profile_installed && fail "legacy RemoveMacAI profile is installed; run '$0 revert' first"
  validate_uaf_catalog
  local sets
  sets="$(sets_to_remove)"

  printf 'Features to disable:\n'
  local f
  for f in "${FEATURES[@]}"; do kept "$f" || printf '  - %s\n' "$(feature_title "$f")"; done
  printf 'Model sets to reset:\n%s\n' "$(printf '%s\n' "$sets" | sed 's/^/  - /')"

  if (( DRY_RUN == 1 )); then
    local dry="${TMPDIR:-/tmp}/Apple-AI-remover.$$.mobileconfig"
    build_profile "$dry" "$sets"
    info 'DRY RUN: no profile was installed and no model was reset.'
    info "generated profile: $dry"
    return 0
  fi

  confirm || { info 'Nothing changed.'; return 0; }

  local expected
  expected="$(keep_csv)"
  build_profile "$PROFILE_FILE" "$sets"
  open "$PROFILE_FILE" 2>/dev/null || true
  open_profile_settings
  info "Approve '$PROFILE_NAME' in System Settings."
  wait_for_profile "$expected" || fail 'profile installation was not observed; no model reset was attempted'

  if [[ -n "$sets" ]]; then
    if reset_models "$sets"; then
      info 'All selected model sets reset successfully.'
    else
      fail 'profile is installed, but one or more model resets failed; run status to inspect remaining model state'
    fi
  fi
  info "Done. Run: $0 status"
}

revert_command() {
  build_helper
  local current=0 legacy=0
  profile_installed && current=1
  legacy_profile_installed && legacy=1
  if (( current == 0 && legacy == 0 )); then info 'No Apple AI remover profile is installed.'; return 0; fi
  if (( YES == 0 )); then
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
  local f set x saved_keep all a b
  for f in "${FEATURES[@]}"; do
    feature_title "$f" >/dev/null || fail "missing title for $f"
    while IFS= read -r x; do
      [[ -z "$x" ]] && continue
      model_set_asset_type "$x" >/dev/null || fail "unknown model set $x referenced by $f"
    done < <(feature_model_sets "$f")
  done
  for set in "${MODEL_SETS[@]}"; do model_set_asset_type "$set" >/dev/null || fail "missing model-set mapping $set"; done

  saved_keep=("${KEEP[@]}")
  KEEP=()
  all="$(sets_to_remove)"
  [[ "$(printf '%s\n' "$all" | sort)" == "$(printf '%s\n' "${MODEL_SETS[@]}" | sort)" ]] || fail 'empty keep set must remove every model set'

  KEEP=(writing-tools)
  all="$(sets_to_remove)"
  ! grep -qx 'com.apple.modelcatalog' <<< "$all" || fail 'writing-tools must protect foundation models'
  grep -qx 'com.apple.MobileAsset.UAF.FM.Visual' <<< "$all" || fail 'writing-tools unexpectedly protects visual models'
  KEEP=("${saved_keep[@]}")

  a="$(stable_uuid "$PROFILE_ID")"; b="$(stable_uuid "$PROFILE_ID")"; [[ "$a" == "$b" ]] || fail 'payload UUID generator is not stable'
  printf 'selftest: PASS (%s features, %s model sets)\n' "${#FEATURES[@]}" "${#MODEL_SETS[@]}"
}

usage() {
  cat <<EOF_USAGE
$PRODUCT_NAME $VERSION

Usage:
  $0 status
  $0 features
  $0 off [--keep feature[,feature...]] [--dry-run] [--yes]
  $0 revert [--yes]
  $0 selftest

The mutating commands target macOS $TARGET_MAJOR.x on Apple silicon.
EOF_USAGE
}

main() {
  local command="${1:-status}"
  shift || true
  case "$command" in
    status) require_platform; status_command "$@" ;;
    features) [[ "$#" -eq 0 ]] || fail 'features takes no options'; print_features ;;
    off) require_platform; off_command "$@" ;;
    revert) require_platform; parse_args "$@"; revert_command ;;
    selftest) [[ "$#" -eq 0 ]] || fail 'selftest takes no options'; selftest_command ;;
    --help|-h|help) usage ;;
    --version|-v|version) echo "$VERSION" ;;
    *) usage >&2; exit 1 ;;
  esac
}

main "$@"
\n'
    done < <(feature_preferences "$feature")
  done
  while IFS= read -r set; do
    [[ -n "$set" ]] || continue
    key="DownloadServerBaseURLOverride-$(model_set_asset_type "$set")"
    PREF_LINES="${PREF_LINES}com.apple.MobileAsset"$'\t'"${key}"$'\t'"${BLOCKED_URL}"$'\n'
  done <<< "$sets"

  mkdir -p "$(dirname "$output")"
  {
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
    printf '%s\n' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    printf '%s\n' '<plist version="1.0"><dict>'
    printf '%s\n' '<key>PayloadType</key><string>Configuration</string>'
    printf '%s\n' '<key>PayloadVersion</key><integer>1</integer>'
    printf '<key>PayloadIdentifier</key><string>%s</string>\n' "$PROFILE_ID"
    printf '<key>PayloadUUID</key><string>%s</string>\n' "$(stable_uuid "$PROFILE_ID")"
    printf '<key>PayloadDisplayName</key><string>%s</string>\n' "$(xml_escape "$PROFILE_NAME")"
    printf '%s\n' '<key>PayloadDescription</key><string>Disables Apple Intelligence features and prevents selected model sets from being re-downloaded. Remove this profile to undo.</string>'
    printf '%s\n' '<key>PayloadOrganization</key><string>Apple AI remover</string>'
    printf '%s\n' '<key>PayloadScope</key><string>System</string>'
    printf '%s\n' '<key>PayloadRemovalDisallowed</key><false/>'
    printf '%s\n' '<key>PayloadContent</key><array>'

    payload_header com.apple.applicationaccess restrictions 'Apple Intelligence restrictions'
    printf '%s\n' '      <key>PayloadContent</key><dict>'
    for feature in "${FEATURES[@]}"; do
      kept "$feature" && continue
      while IFS= read -r key; do
        [[ -n "$key" ]] && printf '        <key>%s</key><false/>\n' "$(xml_escape "$key")"
      done < <(feature_restrictions "$feature")
    done
    printf '%s\n' '      </dict>' '    </dict>'

    for d in com.apple.assistant.support com.apple.Siri group.com.apple.mail group.com.apple.usernoted com.apple.MobileSMS .GlobalPreferences com.apple.spatialphotosrelive; do
      PREF_LINES=''
      while IFS=$'\t' read -r domain key value; do
        [[ "$domain" == "$d" ]] || continue
        PREF_LINES="${PREF_LINES}${key}"$'\t'"${value}"$'\n'
      done <<< "$ALL_PREFS"
      append_pref_payload "$d" "$d" "Forced settings: $d"
    done

    PREF_LINES=''
    while IFS=$'\t' read -r domain key value; do
      [[ "$domain" == 'com.apple.MobileAsset' ]] || continue
      PREF_LINES="${PREF_LINES}${key}"$'\t'"${value}"$'\n'
    done <<< "$ALL_PREFS"
    append_pref_payload com.apple.MobileAsset MobileAsset 'MobileAsset download overrides'

    PREF_LINES="installed"$'\t'true$'\n'"kept"$'\t'"$(keep_csv)"$'\n'
    append_pref_payload "$PROFILE_ID" marker 'Apple AI remover state'

    printf '%s\n' '</array></dict></plist>'
  } > "$tmp"
  /usr/bin/plutil -lint "$tmp" >/dev/null 2>&1 || { rm -f "$tmp"; fail 'generated profile failed plist validation'; }
  mv "$tmp" "$output"
}

keep_csv() {
  local out='' item
  for item in "${KEEP[@]}"; do
    [[ -n "$out" ]] && out="$out,"
    out="$out$item"
  done
  printf '%s' "$out"
}

helper_pref() { "$HELPER" pref "$1" "$2"; }
profile_installed() { local o; o="$(helper_pref "$PROFILE_ID" installed 2>/dev/null)" || return 1; [[ "$o" == *$'forced=1\tvalue=true'* ]]; }
legacy_profile_installed() { local o; o="$(helper_pref "$LEGACY_PROFILE_ID" installed 2>/dev/null)" || return 1; [[ "$o" == *$'forced=1\tvalue=true'* ]]; }
profile_kept_csv() { local o; o="$(helper_pref "$PROFILE_ID" kept 2>/dev/null)" || return 1; printf '%s' "${o#*value=}"; }

validate_uaf_catalog() {
  local set expected actual
  for set in "${MODEL_SETS[@]}"; do
    expected="$(model_set_asset_type "$set")"
    actual="$($HELPER asset-type "$set")" || fail "UAF asset-set lookup failed for $set"
    [[ "$actual" == "$expected" ]] || fail "UAF mapping mismatch for $set: expected $expected, got $actual"
  done
}

model_bytes() {
  local set="$1" out
  out="$($HELPER bytes "$set" 2>/dev/null)" || return 1
  [[ "$out" =~ ^[0-9]+$ ]] || return 1
  printf '%s' "$out"
}

format_bytes() {
  local b="$1"
  if (( b >= 1000000000 )); then awk -v n="$b" 'BEGIN { printf "%.1f GB", n/1e9 }'
  elif (( b > 0 )); then awk -v n="$b" 'BEGIN { printf "%.0f MB", n/1e6 }'
  else echo '0 MB'; fi
}

feature_state() {
  local feature="$1" domain key want output forced value
  local all=1 any=0
  while IFS=$'\t' read -r domain key want; do
    [[ -n "$domain" ]] || continue
    output="$(helper_pref "$domain" "$key" 2>/dev/null)" || { echo unknown; return; }
    forced="$(printf '%s' "$output" | sed -n 's/.*forced=\([^\t]*\).*/\1/p')"
    value="$(printf '%s' "$output" | sed -n 's/.*value=\([^\t]*\)$/\1/p')"
    [[ "$forced" == 1 && "$value" == "$want" ]] && any=1 || all=0
  done < <(feature_preferences "$feature")
  if (( all == 1 && any == 1 )); then echo locked; return; fi

  case "$feature" in
    chatgpt|writing-tools|genmoji|image-playground|safari-summaries|notes-summaries)
      local restricted_ok=1 r
      while IFS= read -r r; do
        [[ -n "$r" ]] || continue
        output="$(helper_pref com.apple.applicationaccess "$r" 2>/dev/null)" || { echo unknown; return; }
        [[ "$output" == *$'forced=1\tvalue=false'* ]] || restricted_ok=0
      done < <(feature_restrictions "$feature")
      (( restricted_ok == 1 )) && echo locked && return
      ;;
  esac

  if profile_installed && ! kept "$feature" && [[ -z "$(feature_preferences "$feature")" ]] && [[ -z "$(feature_restrictions "$feature")" ]]; then
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
  local feature state set n total=0
  for feature in "${FEATURES[@]}"; do
    state="$(feature_state "$feature")"
    printf '%-44s %s\n' "$(feature_title "$feature")" "$state"
  done
  printf '\nModels on disk\n'
  for set in "${MODEL_SETS[@]}"; do
    if n="$(model_bytes "$set")"; then
      total=$((total+n)); printf '  %-44s %s\n' "$(model_set_title "$set")" "$(format_bytes "$n")"
    else
      printf '  %-44s unknown\n' "$(model_set_title "$set")"
    fi
  done
  printf '  %-44s %s\n' Total "$(format_bytes "$total")"
  printf 'Profile: %s\n' "$(profile_installed && echo installed || echo not-installed)"
}

print_features() {
  local f
  for f in "${FEATURES[@]}"; do printf '%-28s %s\n' "$f" "$(feature_title "$f")"; done
}

open_profile_settings() {
  open 'x-apple.systempreferences:com.apple.Profiles-Settings.extension' 2>/dev/null || open 'x-apple.systempreferences:com.apple.preferences.configurationprofiles' 2>/dev/null || true
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
  printf 'Turn off Apple Intelligence and reset the selected models? [y/N] '
  read -r answer
  [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

off_command() {
  parse_args "$@"
  build_helper
  legacy_profile_installed && fail "legacy RemoveMacAI profile is installed; run '$0 revert' first"
  validate_uaf_catalog
  local sets
  sets="$(sets_to_remove)"

  printf 'Features to disable:\n'
  local f
  for f in "${FEATURES[@]}"; do kept "$f" || printf '  - %s\n' "$(feature_title "$f")"; done
  printf 'Model sets to reset:\n%s\n' "$(printf '%s\n' "$sets" | sed 's/^/  - /')"

  if (( DRY_RUN == 1 )); then
    local dry="${TMPDIR:-/tmp}/Apple-AI-remover.$$.mobileconfig"
    build_profile "$dry" "$sets"
    info 'DRY RUN: no profile was installed and no model was reset.'
    info "generated profile: $dry"
    return 0
  fi

  confirm || { info 'Nothing changed.'; return 0; }

  local expected
  expected="$(keep_csv)"
  build_profile "$PROFILE_FILE" "$sets"
  open "$PROFILE_FILE" 2>/dev/null || true
  open_profile_settings
  info "Approve '$PROFILE_NAME' in System Settings."
  wait_for_profile "$expected" || fail 'profile installation was not observed; no model reset was attempted'

  if [[ -n "$sets" ]]; then
    if reset_models "$sets"; then
      info 'All selected model sets reset successfully.'
    else
      fail 'profile is installed, but one or more model resets failed; run status to inspect remaining model state'
    fi
  fi
  info "Done. Run: $0 status"
}

revert_command() {
  build_helper
  local current=0 legacy=0
  profile_installed && current=1
  legacy_profile_installed && legacy=1
  if (( current == 0 && legacy == 0 )); then info 'No Apple AI remover profile is installed.'; return 0; fi
  if (( YES == 0 )); then
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
  local f set x saved_keep all a b
  for f in "${FEATURES[@]}"; do
    feature_title "$f" >/dev/null || fail "missing title for $f"
    while IFS= read -r x; do
      [[ -z "$x" ]] && continue
      model_set_asset_type "$x" >/dev/null || fail "unknown model set $x referenced by $f"
    done < <(feature_model_sets "$f")
  done
  for set in "${MODEL_SETS[@]}"; do model_set_asset_type "$set" >/dev/null || fail "missing model-set mapping $set"; done

  saved_keep=("${KEEP[@]}")
  KEEP=()
  all="$(sets_to_remove)"
  [[ "$(printf '%s\n' "$all" | sort)" == "$(printf '%s\n' "${MODEL_SETS[@]}" | sort)" ]] || fail 'empty keep set must remove every model set'

  KEEP=(writing-tools)
  all="$(sets_to_remove)"
  ! grep -qx 'com.apple.modelcatalog' <<< "$all" || fail 'writing-tools must protect foundation models'
  grep -qx 'com.apple.MobileAsset.UAF.FM.Visual' <<< "$all" || fail 'writing-tools unexpectedly protects visual models'
  KEEP=("${saved_keep[@]}")

  a="$(stable_uuid "$PROFILE_ID")"; b="$(stable_uuid "$PROFILE_ID")"; [[ "$a" == "$b" ]] || fail 'payload UUID generator is not stable'
  printf 'selftest: PASS (%s features, %s model sets)\n' "${#FEATURES[@]}" "${#MODEL_SETS[@]}"
}

usage() {
  cat <<EOF_USAGE
$PRODUCT_NAME $VERSION

Usage:
  $0 status
  $0 features
  $0 off [--keep feature[,feature...]] [--dry-run] [--yes]
  $0 revert [--yes]
  $0 selftest

The mutating commands target macOS $TARGET_MAJOR.x on Apple silicon.
EOF_USAGE
}

main() {
  local command="${1:-status}"
  shift || true
  case "$command" in
    status) require_platform; status_command "$@" ;;
    features) [[ "$#" -eq 0 ]] || fail 'features takes no options'; print_features ;;
    off) require_platform; off_command "$@" ;;
    revert) require_platform; parse_args "$@"; revert_command ;;
    selftest) [[ "$#" -eq 0 ]] || fail 'selftest takes no options'; selftest_command ;;
    --help|-h|help) usage ;;
    --version|-v|version) echo "$VERSION" ;;
    *) usage >&2; exit 1 ;;
  esac
}

main "$@"
forced=1\tvalue=true'* ]]; }
upstream_profile_installed() { local o; o="$(helper_pref "$UPSTREAM_PROFILE_ID" installed 2>/dev/null)" || return 1; [[ "$o" == * { local o; o="$(helper_pref "$PROFILE_ID" kept 2>/dev/null)" || return 1; printf '%s' "${o#*value=}"; }

validate_uaf_catalog() {
  local set expected actual
  for set in "${MODEL_SETS[@]}"; do
    expected="$(model_set_asset_type "$set")"
    actual="$($HELPER asset-type "$set")" || fail "UAF asset-set lookup failed for $set"
    [[ "$actual" == "$expected" ]] || fail "UAF mapping mismatch for $set: expected $expected, got $actual"
  done
}

model_bytes() {
  local set="$1" out
  out="$($HELPER bytes "$set" 2>/dev/null)" || return 1
  [[ "$out" =~ ^[0-9]+$ ]] || return 1
  printf '%s' "$out"
}

format_bytes() {
  local b="$1"
  if (( b >= 1000000000 )); then awk -v n="$b" 'BEGIN { printf "%.1f GB", n/1e9 }'
  elif (( b > 0 )); then awk -v n="$b" 'BEGIN { printf "%.0f MB", n/1e6 }'
  else echo '0 MB'; fi
}

feature_state() {
  local feature="$1" domain key want output forced value
  local all=1 any=0
  while IFS=$'\t' read -r domain key want; do
    [[ -n "$domain" ]] || continue
    output="$(helper_pref "$domain" "$key" 2>/dev/null)" || { echo unknown; return; }
    forced="$(printf '%s' "$output" | sed -n 's/.*forced=\([^\t]*\).*/\1/p')"
    value="$(printf '%s' "$output" | sed -n 's/.*value=\([^\t]*\)$/\1/p')"
    [[ "$forced" == 1 && "$value" == "$want" ]] && any=1 || all=0
  done < <(feature_preferences "$feature")
  if (( all == 1 && any == 1 )); then echo locked; return; fi

  case "$feature" in
    chatgpt|writing-tools|genmoji|image-playground|safari-summaries|notes-summaries)
      local restricted_ok=1 r
      while IFS= read -r r; do
        [[ -n "$r" ]] || continue
        output="$(helper_pref com.apple.applicationaccess "$r" 2>/dev/null)" || { echo unknown; return; }
        [[ "$output" == *$'forced=1\tvalue=false'* ]] || restricted_ok=0
      done < <(feature_restrictions "$feature")
      (( restricted_ok == 1 )) && echo locked && return
      ;;
  esac

  if profile_installed && ! kept "$feature" && [[ -z "$(feature_preferences "$feature")" ]] && [[ -z "$(feature_restrictions "$feature")" ]]; then
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
  local feature state set n total=0
  for feature in "${FEATURES[@]}"; do
    state="$(feature_state "$feature")"
    printf '%-44s %s\n' "$(feature_title "$feature")" "$state"
  done
  printf '\nModels on disk\n'
  for set in "${MODEL_SETS[@]}"; do
    if n="$(model_bytes "$set")"; then
      total=$((total+n)); printf '  %-44s %s\n' "$(model_set_title "$set")" "$(format_bytes "$n")"
    else
      printf '  %-44s unknown\n' "$(model_set_title "$set")"
    fi
  done
  printf '  %-44s %s\n' Total "$(format_bytes "$total")"
  printf 'Profile: %s\n' "$(profile_installed && echo installed || echo not-installed)"
}

print_features() {
  local f
  for f in "${FEATURES[@]}"; do printf '%-28s %s\n' "$f" "$(feature_title "$f")"; done
}

open_profile_settings() {
  open 'x-apple.systempreferences:com.apple.Profiles-Settings.extension' 2>/dev/null || open 'x-apple.systempreferences:com.apple.preferences.configurationprofiles' 2>/dev/null || true
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
  printf 'Turn off Apple Intelligence and reset the selected models? [y/N] '
  read -r answer
  [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

off_command() {
  parse_args "$@"
  build_helper
  legacy_profile_installed && fail "legacy RemoveMacAI profile is installed; run '$0 revert' first"
  validate_uaf_catalog
  local sets
  sets="$(sets_to_remove)"

  printf 'Features to disable:\n'
  local f
  for f in "${FEATURES[@]}"; do kept "$f" || printf '  - %s\n' "$(feature_title "$f")"; done
  printf 'Model sets to reset:\n%s\n' "$(printf '%s\n' "$sets" | sed 's/^/  - /')"

  if (( DRY_RUN == 1 )); then
    local dry="${TMPDIR:-/tmp}/Apple-AI-remover.$$.mobileconfig"
    build_profile "$dry" "$sets"
    info 'DRY RUN: no profile was installed and no model was reset.'
    info "generated profile: $dry"
    return 0
  fi

  confirm || { info 'Nothing changed.'; return 0; }

  local expected
  expected="$(keep_csv)"
  build_profile "$PROFILE_FILE" "$sets"
  open "$PROFILE_FILE" 2>/dev/null || true
  open_profile_settings
  info "Approve '$PROFILE_NAME' in System Settings."
  wait_for_profile "$expected" || fail 'profile installation was not observed; no model reset was attempted'

  if [[ -n "$sets" ]]; then
    if reset_models "$sets"; then
      info 'All selected model sets reset successfully.'
    else
      fail 'profile is installed, but one or more model resets failed; run status to inspect remaining model state'
    fi
  fi
  info "Done. Run: $0 status"
}

revert_command() {
  build_helper
  local current=0 legacy=0
  profile_installed && current=1
  legacy_profile_installed && legacy=1
  if (( current == 0 && legacy == 0 )); then info 'No Apple AI remover profile is installed.'; return 0; fi
  if (( YES == 0 )); then
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
  local f set x saved_keep all a b
  for f in "${FEATURES[@]}"; do
    feature_title "$f" >/dev/null || fail "missing title for $f"
    while IFS= read -r x; do
      [[ -z "$x" ]] && continue
      model_set_asset_type "$x" >/dev/null || fail "unknown model set $x referenced by $f"
    done < <(feature_model_sets "$f")
  done
  for set in "${MODEL_SETS[@]}"; do model_set_asset_type "$set" >/dev/null || fail "missing model-set mapping $set"; done

  saved_keep=("${KEEP[@]}")
  KEEP=()
  all="$(sets_to_remove)"
  [[ "$(printf '%s\n' "$all" | sort)" == "$(printf '%s\n' "${MODEL_SETS[@]}" | sort)" ]] || fail 'empty keep set must remove every model set'

  KEEP=(writing-tools)
  all="$(sets_to_remove)"
  ! grep -qx 'com.apple.modelcatalog' <<< "$all" || fail 'writing-tools must protect foundation models'
  grep -qx 'com.apple.MobileAsset.UAF.FM.Visual' <<< "$all" || fail 'writing-tools unexpectedly protects visual models'
  KEEP=("${saved_keep[@]}")

  a="$(stable_uuid "$PROFILE_ID")"; b="$(stable_uuid "$PROFILE_ID")"; [[ "$a" == "$b" ]] || fail 'payload UUID generator is not stable'
  printf 'selftest: PASS (%s features, %s model sets)\n' "${#FEATURES[@]}" "${#MODEL_SETS[@]}"
}

usage() {
  cat <<EOF_USAGE
$PRODUCT_NAME $VERSION

Usage:
  $0 status
  $0 features
  $0 off [--keep feature[,feature...]] [--dry-run] [--yes]
  $0 revert [--yes]
  $0 selftest

The mutating commands target macOS $TARGET_MAJOR.x on Apple silicon.
EOF_USAGE
}

main() {
  local command="${1:-status}"
  shift || true
  case "$command" in
    status) require_platform; status_command "$@" ;;
    features) [[ "$#" -eq 0 ]] || fail 'features takes no options'; print_features ;;
    off) require_platform; off_command "$@" ;;
    revert) require_platform; parse_args "$@"; revert_command ;;
    selftest) [[ "$#" -eq 0 ]] || fail 'selftest takes no options'; selftest_command ;;
    --help|-h|help) usage ;;
    --version|-v|version) echo "$VERSION" ;;
    *) usage >&2; exit 1 ;;
  esac
}

main "$@"
\t'"${key}"
    [[ -n "$set" ]] || continue
    key="DownloadServerBaseURLOverride-$(model_set_asset_type "$set")"
    PREF_LINES="${PREF_LINES}com.apple.MobileAsset"$'\t'"${key}"$'\t'"${BLOCKED_URL}"$'\n'
  done <<< "$sets"

  mkdir -p "$(dirname "$output")"
  {
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
    printf '%s\n' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    printf '%s\n' '<plist version="1.0"><dict>'
    printf '%s\n' '<key>PayloadType</key><string>Configuration</string>'
    printf '%s\n' '<key>PayloadVersion</key><integer>1</integer>'
    printf '<key>PayloadIdentifier</key><string>%s</string>\n' "$PROFILE_ID"
    printf '<key>PayloadUUID</key><string>%s</string>\n' "$(stable_uuid "$PROFILE_ID")"
    printf '<key>PayloadDisplayName</key><string>%s</string>\n' "$(xml_escape "$PROFILE_NAME")"
    printf '%s\n' '<key>PayloadDescription</key><string>Disables Apple Intelligence features and prevents selected model sets from being re-downloaded. Remove this profile to undo.</string>'
    printf '%s\n' '<key>PayloadOrganization</key><string>Apple AI remover</string>'
    printf '%s\n' '<key>PayloadScope</key><string>System</string>'
    printf '%s\n' '<key>PayloadRemovalDisallowed</key><false/>'
    printf '%s\n' '<key>PayloadContent</key><array>'

    payload_header com.apple.applicationaccess restrictions 'Apple Intelligence restrictions'
    printf '%s\n' '      <key>PayloadContent</key><dict>'
    for feature in "${FEATURES[@]}"; do
      kept "$feature" && continue
      while IFS= read -r key; do
        [[ -n "$key" ]] && printf '        <key>%s</key><false/>\n' "$(xml_escape "$key")"
      done < <(feature_restrictions "$feature")
    done
    printf '%s\n' '      </dict>' '    </dict>'

    for d in com.apple.assistant.support com.apple.Siri group.com.apple.mail group.com.apple.usernoted com.apple.MobileSMS .GlobalPreferences com.apple.spatialphotosrelive; do
      PREF_LINES=''
      while IFS=$'\t' read -r domain key value; do
        [[ "$domain" == "$d" ]] || continue
        PREF_LINES="${PREF_LINES}${key}"$'\t'"${value}"$'\n'
      done <<< "$ALL_PREFS"
      append_pref_payload "$d" "$d" "Forced settings: $d"
    done

    PREF_LINES=''
    while IFS=$'\t' read -r domain key value; do
      [[ "$domain" == 'com.apple.MobileAsset' ]] || continue
      PREF_LINES="${PREF_LINES}${key}"$'\t'"${value}"$'\n'
    done <<< "$ALL_PREFS"
    append_pref_payload com.apple.MobileAsset MobileAsset 'MobileAsset download overrides'

    PREF_LINES="installed"$'\t'true$'\n'"kept"$'\t'"$(keep_csv)"$'\n'
    append_pref_payload "$PROFILE_ID" marker 'Apple AI remover state'

    printf '%s\n' '</array></dict></plist>'
  } > "$tmp"
  /usr/bin/plutil -lint "$tmp" >/dev/null 2>&1 || { rm -f "$tmp"; fail 'generated profile failed plist validation'; }
  mv "$tmp" "$output"
}

keep_csv() {
  local out='' item
  for item in "${KEEP[@]}"; do
    [[ -n "$out" ]] && out="$out,"
    out="$out$item"
  done
  printf '%s' "$out"
}

helper_pref() { "$HELPER" pref "$1" "$2"; }
profile_installed() { local o; o="$(helper_pref "$PROFILE_ID" installed 2>/dev/null)" || return 1; [[ "$o" == *$'forced=1\tvalue=true'* ]]; }
legacy_profile_installed() { local o; o="$(helper_pref "$LEGACY_PROFILE_ID" installed 2>/dev/null)" || return 1; [[ "$o" == *$'forced=1\tvalue=true'* ]]; }
profile_kept_csv() { local o; o="$(helper_pref "$PROFILE_ID" kept 2>/dev/null)" || return 1; printf '%s' "${o#*value=}"; }

validate_uaf_catalog() {
  local set expected actual
  for set in "${MODEL_SETS[@]}"; do
    expected="$(model_set_asset_type "$set")"
    actual="$($HELPER asset-type "$set")" || fail "UAF asset-set lookup failed for $set"
    [[ "$actual" == "$expected" ]] || fail "UAF mapping mismatch for $set: expected $expected, got $actual"
  done
}

model_bytes() {
  local set="$1" out
  out="$($HELPER bytes "$set" 2>/dev/null)" || return 1
  [[ "$out" =~ ^[0-9]+$ ]] || return 1
  printf '%s' "$out"
}

format_bytes() {
  local b="$1"
  if (( b >= 1000000000 )); then awk -v n="$b" 'BEGIN { printf "%.1f GB", n/1e9 }'
  elif (( b > 0 )); then awk -v n="$b" 'BEGIN { printf "%.0f MB", n/1e6 }'
  else echo '0 MB'; fi
}

feature_state() {
  local feature="$1" domain key want output forced value
  local all=1 any=0
  while IFS=$'\t' read -r domain key want; do
    [[ -n "$domain" ]] || continue
    output="$(helper_pref "$domain" "$key" 2>/dev/null)" || { echo unknown; return; }
    forced="$(printf '%s' "$output" | sed -n 's/.*forced=\([^\t]*\).*/\1/p')"
    value="$(printf '%s' "$output" | sed -n 's/.*value=\([^\t]*\)$/\1/p')"
    [[ "$forced" == 1 && "$value" == "$want" ]] && any=1 || all=0
  done < <(feature_preferences "$feature")
  if (( all == 1 && any == 1 )); then echo locked; return; fi

  case "$feature" in
    chatgpt|writing-tools|genmoji|image-playground|safari-summaries|notes-summaries)
      local restricted_ok=1 r
      while IFS= read -r r; do
        [[ -n "$r" ]] || continue
        output="$(helper_pref com.apple.applicationaccess "$r" 2>/dev/null)" || { echo unknown; return; }
        [[ "$output" == *$'forced=1\tvalue=false'* ]] || restricted_ok=0
      done < <(feature_restrictions "$feature")
      (( restricted_ok == 1 )) && echo locked && return
      ;;
  esac

  if profile_installed && ! kept "$feature" && [[ -z "$(feature_preferences "$feature")" ]] && [[ -z "$(feature_restrictions "$feature")" ]]; then
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
  local feature state set n total=0
  for feature in "${FEATURES[@]}"; do
    state="$(feature_state "$feature")"
    printf '%-44s %s\n' "$(feature_title "$feature")" "$state"
  done
  printf '\nModels on disk\n'
  for set in "${MODEL_SETS[@]}"; do
    if n="$(model_bytes "$set")"; then
      total=$((total+n)); printf '  %-44s %s\n' "$(model_set_title "$set")" "$(format_bytes "$n")"
    else
      printf '  %-44s unknown\n' "$(model_set_title "$set")"
    fi
  done
  printf '  %-44s %s\n' Total "$(format_bytes "$total")"
  printf 'Profile: %s\n' "$(profile_installed && echo installed || echo not-installed)"
}

print_features() {
  local f
  for f in "${FEATURES[@]}"; do printf '%-28s %s\n' "$f" "$(feature_title "$f")"; done
}

open_profile_settings() {
  open 'x-apple.systempreferences:com.apple.Profiles-Settings.extension' 2>/dev/null || open 'x-apple.systempreferences:com.apple.preferences.configurationprofiles' 2>/dev/null || true
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
  printf 'Turn off Apple Intelligence and reset the selected models? [y/N] '
  read -r answer
  [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

off_command() {
  parse_args "$@"
  build_helper
  legacy_profile_installed && fail "legacy RemoveMacAI profile is installed; run '$0 revert' first"
  validate_uaf_catalog
  local sets
  sets="$(sets_to_remove)"

  printf 'Features to disable:\n'
  local f
  for f in "${FEATURES[@]}"; do kept "$f" || printf '  - %s\n' "$(feature_title "$f")"; done
  printf 'Model sets to reset:\n%s\n' "$(printf '%s\n' "$sets" | sed 's/^/  - /')"

  if (( DRY_RUN == 1 )); then
    local dry="${TMPDIR:-/tmp}/Apple-AI-remover.$$.mobileconfig"
    build_profile "$dry" "$sets"
    info 'DRY RUN: no profile was installed and no model was reset.'
    info "generated profile: $dry"
    return 0
  fi

  confirm || { info 'Nothing changed.'; return 0; }

  local expected
  expected="$(keep_csv)"
  build_profile "$PROFILE_FILE" "$sets"
  open "$PROFILE_FILE" 2>/dev/null || true
  open_profile_settings
  info "Approve '$PROFILE_NAME' in System Settings."
  wait_for_profile "$expected" || fail 'profile installation was not observed; no model reset was attempted'

  if [[ -n "$sets" ]]; then
    if reset_models "$sets"; then
      info 'All selected model sets reset successfully.'
    else
      fail 'profile is installed, but one or more model resets failed; run status to inspect remaining model state'
    fi
  fi
  info "Done. Run: $0 status"
}

revert_command() {
  build_helper
  local current=0 legacy=0
  profile_installed && current=1
  legacy_profile_installed && legacy=1
  if (( current == 0 && legacy == 0 )); then info 'No Apple AI remover profile is installed.'; return 0; fi
  if (( YES == 0 )); then
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
  local f set x saved_keep all a b
  for f in "${FEATURES[@]}"; do
    feature_title "$f" >/dev/null || fail "missing title for $f"
    while IFS= read -r x; do
      [[ -z "$x" ]] && continue
      model_set_asset_type "$x" >/dev/null || fail "unknown model set $x referenced by $f"
    done < <(feature_model_sets "$f")
  done
  for set in "${MODEL_SETS[@]}"; do model_set_asset_type "$set" >/dev/null || fail "missing model-set mapping $set"; done

  saved_keep=("${KEEP[@]}")
  KEEP=()
  all="$(sets_to_remove)"
  [[ "$(printf '%s\n' "$all" | sort)" == "$(printf '%s\n' "${MODEL_SETS[@]}" | sort)" ]] || fail 'empty keep set must remove every model set'

  KEEP=(writing-tools)
  all="$(sets_to_remove)"
  ! grep -qx 'com.apple.modelcatalog' <<< "$all" || fail 'writing-tools must protect foundation models'
  grep -qx 'com.apple.MobileAsset.UAF.FM.Visual' <<< "$all" || fail 'writing-tools unexpectedly protects visual models'
  KEEP=("${saved_keep[@]}")

  a="$(stable_uuid "$PROFILE_ID")"; b="$(stable_uuid "$PROFILE_ID")"; [[ "$a" == "$b" ]] || fail 'payload UUID generator is not stable'
  printf 'selftest: PASS (%s features, %s model sets)\n' "${#FEATURES[@]}" "${#MODEL_SETS[@]}"
}

usage() {
  cat <<EOF_USAGE
$PRODUCT_NAME $VERSION

Usage:
  $0 status
  $0 features
  $0 off [--keep feature[,feature...]] [--dry-run] [--yes]
  $0 revert [--yes]
  $0 selftest

The mutating commands target macOS $TARGET_MAJOR.x on Apple silicon.
EOF_USAGE
}

main() {
  local command="${1:-status}"
  shift || true
  case "$command" in
    status) require_platform; status_command "$@" ;;
    features) [[ "$#" -eq 0 ]] || fail 'features takes no options'; print_features ;;
    off) require_platform; off_command "$@" ;;
    revert) require_platform; parse_args "$@"; revert_command ;;
    selftest) [[ "$#" -eq 0 ]] || fail 'selftest takes no options'; selftest_command ;;
    --help|-h|help) usage ;;
    --version|-v|version) echo "$VERSION" ;;
    *) usage >&2; exit 1 ;;
  esac
}

main "$@"
\t'"${value}"
    [[ -n "$set" ]] || continue
    key="DownloadServerBaseURLOverride-$(model_set_asset_type "$set")"
    PREF_LINES="${PREF_LINES}com.apple.MobileAsset"$'\t'"${key}"$'\t'"${BLOCKED_URL}"$'\n'
  done <<< "$sets"

  mkdir -p "$(dirname "$output")"
  {
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
    printf '%s\n' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    printf '%s\n' '<plist version="1.0"><dict>'
    printf '%s\n' '<key>PayloadType</key><string>Configuration</string>'
    printf '%s\n' '<key>PayloadVersion</key><integer>1</integer>'
    printf '<key>PayloadIdentifier</key><string>%s</string>\n' "$PROFILE_ID"
    printf '<key>PayloadUUID</key><string>%s</string>\n' "$(stable_uuid "$PROFILE_ID")"
    printf '<key>PayloadDisplayName</key><string>%s</string>\n' "$(xml_escape "$PROFILE_NAME")"
    printf '%s\n' '<key>PayloadDescription</key><string>Disables Apple Intelligence features and prevents selected model sets from being re-downloaded. Remove this profile to undo.</string>'
    printf '%s\n' '<key>PayloadOrganization</key><string>Apple AI remover</string>'
    printf '%s\n' '<key>PayloadScope</key><string>System</string>'
    printf '%s\n' '<key>PayloadRemovalDisallowed</key><false/>'
    printf '%s\n' '<key>PayloadContent</key><array>'

    payload_header com.apple.applicationaccess restrictions 'Apple Intelligence restrictions'
    printf '%s\n' '      <key>PayloadContent</key><dict>'
    for feature in "${FEATURES[@]}"; do
      kept "$feature" && continue
      while IFS= read -r key; do
        [[ -n "$key" ]] && printf '        <key>%s</key><false/>\n' "$(xml_escape "$key")"
      done < <(feature_restrictions "$feature")
    done
    printf '%s\n' '      </dict>' '    </dict>'

    for d in com.apple.assistant.support com.apple.Siri group.com.apple.mail group.com.apple.usernoted com.apple.MobileSMS .GlobalPreferences com.apple.spatialphotosrelive; do
      PREF_LINES=''
      while IFS=$'\t' read -r domain key value; do
        [[ "$domain" == "$d" ]] || continue
        PREF_LINES="${PREF_LINES}${key}"$'\t'"${value}"$'\n'
      done <<< "$ALL_PREFS"
      append_pref_payload "$d" "$d" "Forced settings: $d"
    done

    PREF_LINES=''
    while IFS=$'\t' read -r domain key value; do
      [[ "$domain" == 'com.apple.MobileAsset' ]] || continue
      PREF_LINES="${PREF_LINES}${key}"$'\t'"${value}"$'\n'
    done <<< "$ALL_PREFS"
    append_pref_payload com.apple.MobileAsset MobileAsset 'MobileAsset download overrides'

    PREF_LINES="installed"$'\t'true$'\n'"kept"$'\t'"$(keep_csv)"$'\n'
    append_pref_payload "$PROFILE_ID" marker 'Apple AI remover state'

    printf '%s\n' '</array></dict></plist>'
  } > "$tmp"
  /usr/bin/plutil -lint "$tmp" >/dev/null 2>&1 || { rm -f "$tmp"; fail 'generated profile failed plist validation'; }
  mv "$tmp" "$output"
}

keep_csv() {
  local out='' item
  for item in "${KEEP[@]}"; do
    [[ -n "$out" ]] && out="$out,"
    out="$out$item"
  done
  printf '%s' "$out"
}

helper_pref() { "$HELPER" pref "$1" "$2"; }
profile_installed() { local o; o="$(helper_pref "$PROFILE_ID" installed 2>/dev/null)" || return 1; [[ "$o" == *$'forced=1\tvalue=true'* ]]; }
legacy_profile_installed() { local o; o="$(helper_pref "$LEGACY_PROFILE_ID" installed 2>/dev/null)" || return 1; [[ "$o" == *$'forced=1\tvalue=true'* ]]; }
profile_kept_csv() { local o; o="$(helper_pref "$PROFILE_ID" kept 2>/dev/null)" || return 1; printf '%s' "${o#*value=}"; }

validate_uaf_catalog() {
  local set expected actual
  for set in "${MODEL_SETS[@]}"; do
    expected="$(model_set_asset_type "$set")"
    actual="$($HELPER asset-type "$set")" || fail "UAF asset-set lookup failed for $set"
    [[ "$actual" == "$expected" ]] || fail "UAF mapping mismatch for $set: expected $expected, got $actual"
  done
}

model_bytes() {
  local set="$1" out
  out="$($HELPER bytes "$set" 2>/dev/null)" || return 1
  [[ "$out" =~ ^[0-9]+$ ]] || return 1
  printf '%s' "$out"
}

format_bytes() {
  local b="$1"
  if (( b >= 1000000000 )); then awk -v n="$b" 'BEGIN { printf "%.1f GB", n/1e9 }'
  elif (( b > 0 )); then awk -v n="$b" 'BEGIN { printf "%.0f MB", n/1e6 }'
  else echo '0 MB'; fi
}

feature_state() {
  local feature="$1" domain key want output forced value
  local all=1 any=0
  while IFS=$'\t' read -r domain key want; do
    [[ -n "$domain" ]] || continue
    output="$(helper_pref "$domain" "$key" 2>/dev/null)" || { echo unknown; return; }
    forced="$(printf '%s' "$output" | sed -n 's/.*forced=\([^\t]*\).*/\1/p')"
    value="$(printf '%s' "$output" | sed -n 's/.*value=\([^\t]*\)$/\1/p')"
    [[ "$forced" == 1 && "$value" == "$want" ]] && any=1 || all=0
  done < <(feature_preferences "$feature")
  if (( all == 1 && any == 1 )); then echo locked; return; fi

  case "$feature" in
    chatgpt|writing-tools|genmoji|image-playground|safari-summaries|notes-summaries)
      local restricted_ok=1 r
      while IFS= read -r r; do
        [[ -n "$r" ]] || continue
        output="$(helper_pref com.apple.applicationaccess "$r" 2>/dev/null)" || { echo unknown; return; }
        [[ "$output" == *$'forced=1\tvalue=false'* ]] || restricted_ok=0
      done < <(feature_restrictions "$feature")
      (( restricted_ok == 1 )) && echo locked && return
      ;;
  esac

  if profile_installed && ! kept "$feature" && [[ -z "$(feature_preferences "$feature")" ]] && [[ -z "$(feature_restrictions "$feature")" ]]; then
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
  local feature state set n total=0
  for feature in "${FEATURES[@]}"; do
    state="$(feature_state "$feature")"
    printf '%-44s %s\n' "$(feature_title "$feature")" "$state"
  done
  printf '\nModels on disk\n'
  for set in "${MODEL_SETS[@]}"; do
    if n="$(model_bytes "$set")"; then
      total=$((total+n)); printf '  %-44s %s\n' "$(model_set_title "$set")" "$(format_bytes "$n")"
    else
      printf '  %-44s unknown\n' "$(model_set_title "$set")"
    fi
  done
  printf '  %-44s %s\n' Total "$(format_bytes "$total")"
  printf 'Profile: %s\n' "$(profile_installed && echo installed || echo not-installed)"
}

print_features() {
  local f
  for f in "${FEATURES[@]}"; do printf '%-28s %s\n' "$f" "$(feature_title "$f")"; done
}

open_profile_settings() {
  open 'x-apple.systempreferences:com.apple.Profiles-Settings.extension' 2>/dev/null || open 'x-apple.systempreferences:com.apple.preferences.configurationprofiles' 2>/dev/null || true
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
  printf 'Turn off Apple Intelligence and reset the selected models? [y/N] '
  read -r answer
  [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

off_command() {
  parse_args "$@"
  build_helper
  legacy_profile_installed && fail "legacy RemoveMacAI profile is installed; run '$0 revert' first"
  validate_uaf_catalog
  local sets
  sets="$(sets_to_remove)"

  printf 'Features to disable:\n'
  local f
  for f in "${FEATURES[@]}"; do kept "$f" || printf '  - %s\n' "$(feature_title "$f")"; done
  printf 'Model sets to reset:\n%s\n' "$(printf '%s\n' "$sets" | sed 's/^/  - /')"

  if (( DRY_RUN == 1 )); then
    local dry="${TMPDIR:-/tmp}/Apple-AI-remover.$$.mobileconfig"
    build_profile "$dry" "$sets"
    info 'DRY RUN: no profile was installed and no model was reset.'
    info "generated profile: $dry"
    return 0
  fi

  confirm || { info 'Nothing changed.'; return 0; }

  local expected
  expected="$(keep_csv)"
  build_profile "$PROFILE_FILE" "$sets"
  open "$PROFILE_FILE" 2>/dev/null || true
  open_profile_settings
  info "Approve '$PROFILE_NAME' in System Settings."
  wait_for_profile "$expected" || fail 'profile installation was not observed; no model reset was attempted'

  if [[ -n "$sets" ]]; then
    if reset_models "$sets"; then
      info 'All selected model sets reset successfully.'
    else
      fail 'profile is installed, but one or more model resets failed; run status to inspect remaining model state'
    fi
  fi
  info "Done. Run: $0 status"
}

revert_command() {
  build_helper
  local current=0 legacy=0
  profile_installed && current=1
  legacy_profile_installed && legacy=1
  if (( current == 0 && legacy == 0 )); then info 'No Apple AI remover profile is installed.'; return 0; fi
  if (( YES == 0 )); then
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
  local f set x saved_keep all a b
  for f in "${FEATURES[@]}"; do
    feature_title "$f" >/dev/null || fail "missing title for $f"
    while IFS= read -r x; do
      [[ -z "$x" ]] && continue
      model_set_asset_type "$x" >/dev/null || fail "unknown model set $x referenced by $f"
    done < <(feature_model_sets "$f")
  done
  for set in "${MODEL_SETS[@]}"; do model_set_asset_type "$set" >/dev/null || fail "missing model-set mapping $set"; done

  saved_keep=("${KEEP[@]}")
  KEEP=()
  all="$(sets_to_remove)"
  [[ "$(printf '%s\n' "$all" | sort)" == "$(printf '%s\n' "${MODEL_SETS[@]}" | sort)" ]] || fail 'empty keep set must remove every model set'

  KEEP=(writing-tools)
  all="$(sets_to_remove)"
  ! grep -qx 'com.apple.modelcatalog' <<< "$all" || fail 'writing-tools must protect foundation models'
  grep -qx 'com.apple.MobileAsset.UAF.FM.Visual' <<< "$all" || fail 'writing-tools unexpectedly protects visual models'
  KEEP=("${saved_keep[@]}")

  a="$(stable_uuid "$PROFILE_ID")"; b="$(stable_uuid "$PROFILE_ID")"; [[ "$a" == "$b" ]] || fail 'payload UUID generator is not stable'
  printf 'selftest: PASS (%s features, %s model sets)\n' "${#FEATURES[@]}" "${#MODEL_SETS[@]}"
}

usage() {
  cat <<EOF_USAGE
$PRODUCT_NAME $VERSION

Usage:
  $0 status
  $0 features
  $0 off [--keep feature[,feature...]] [--dry-run] [--yes]
  $0 revert [--yes]
  $0 selftest

The mutating commands target macOS $TARGET_MAJOR.x on Apple silicon.
EOF_USAGE
}

main() {
  local command="${1:-status}"
  shift || true
  case "$command" in
    status) require_platform; status_command "$@" ;;
    features) [[ "$#" -eq 0 ]] || fail 'features takes no options'; print_features ;;
    off) require_platform; off_command "$@" ;;
    revert) require_platform; parse_args "$@"; revert_command ;;
    selftest) [[ "$#" -eq 0 ]] || fail 'selftest takes no options'; selftest_command ;;
    --help|-h|help) usage ;;
    --version|-v|version) echo "$VERSION" ;;
    *) usage >&2; exit 1 ;;
  esac
}

main "$@"
\n'
    done < <(feature_preferences "$feature")
  done
  while IFS= read -r set; do
    [[ -n "$set" ]] || continue
    key="DownloadServerBaseURLOverride-$(model_set_asset_type "$set")"
    PREF_LINES="${PREF_LINES}com.apple.MobileAsset"$'\t'"${key}"$'\t'"${BLOCKED_URL}"$'\n'
  done <<< "$sets"

  mkdir -p "$(dirname "$output")"
  {
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
    printf '%s\n' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    printf '%s\n' '<plist version="1.0"><dict>'
    printf '%s\n' '<key>PayloadType</key><string>Configuration</string>'
    printf '%s\n' '<key>PayloadVersion</key><integer>1</integer>'
    printf '<key>PayloadIdentifier</key><string>%s</string>\n' "$PROFILE_ID"
    printf '<key>PayloadUUID</key><string>%s</string>\n' "$(stable_uuid "$PROFILE_ID")"
    printf '<key>PayloadDisplayName</key><string>%s</string>\n' "$(xml_escape "$PROFILE_NAME")"
    printf '%s\n' '<key>PayloadDescription</key><string>Disables Apple Intelligence features and prevents selected model sets from being re-downloaded. Remove this profile to undo.</string>'
    printf '%s\n' '<key>PayloadOrganization</key><string>Apple AI remover</string>'
    printf '%s\n' '<key>PayloadScope</key><string>System</string>'
    printf '%s\n' '<key>PayloadRemovalDisallowed</key><false/>'
    printf '%s\n' '<key>PayloadContent</key><array>'

    payload_header com.apple.applicationaccess restrictions 'Apple Intelligence restrictions'
    printf '%s\n' '      <key>PayloadContent</key><dict>'
    for feature in "${FEATURES[@]}"; do
      kept "$feature" && continue
      while IFS= read -r key; do
        [[ -n "$key" ]] && printf '        <key>%s</key><false/>\n' "$(xml_escape "$key")"
      done < <(feature_restrictions "$feature")
    done
    printf '%s\n' '      </dict>' '    </dict>'

    for d in com.apple.assistant.support com.apple.Siri group.com.apple.mail group.com.apple.usernoted com.apple.MobileSMS .GlobalPreferences com.apple.spatialphotosrelive; do
      PREF_LINES=''
      while IFS=$'\t' read -r domain key value; do
        [[ "$domain" == "$d" ]] || continue
        PREF_LINES="${PREF_LINES}${key}"$'\t'"${value}"$'\n'
      done <<< "$ALL_PREFS"
      append_pref_payload "$d" "$d" "Forced settings: $d"
    done

    PREF_LINES=''
    while IFS=$'\t' read -r domain key value; do
      [[ "$domain" == 'com.apple.MobileAsset' ]] || continue
      PREF_LINES="${PREF_LINES}${key}"$'\t'"${value}"$'\n'
    done <<< "$ALL_PREFS"
    append_pref_payload com.apple.MobileAsset MobileAsset 'MobileAsset download overrides'

    PREF_LINES="installed"$'\t'true$'\n'"kept"$'\t'"$(keep_csv)"$'\n'
    append_pref_payload "$PROFILE_ID" marker 'Apple AI remover state'

    printf '%s\n' '</array></dict></plist>'
  } > "$tmp"
  /usr/bin/plutil -lint "$tmp" >/dev/null 2>&1 || { rm -f "$tmp"; fail 'generated profile failed plist validation'; }
  mv "$tmp" "$output"
}

keep_csv() {
  local out='' item
  for item in "${KEEP[@]}"; do
    [[ -n "$out" ]] && out="$out,"
    out="$out$item"
  done
  printf '%s' "$out"
}

helper_pref() { "$HELPER" pref "$1" "$2"; }
profile_installed() { local o; o="$(helper_pref "$PROFILE_ID" installed 2>/dev/null)" || return 1; [[ "$o" == *$'forced=1\tvalue=true'* ]]; }
legacy_profile_installed() { local o; o="$(helper_pref "$LEGACY_PROFILE_ID" installed 2>/dev/null)" || return 1; [[ "$o" == *$'forced=1\tvalue=true'* ]]; }
profile_kept_csv() { local o; o="$(helper_pref "$PROFILE_ID" kept 2>/dev/null)" || return 1; printf '%s' "${o#*value=}"; }

validate_uaf_catalog() {
  local set expected actual
  for set in "${MODEL_SETS[@]}"; do
    expected="$(model_set_asset_type "$set")"
    actual="$($HELPER asset-type "$set")" || fail "UAF asset-set lookup failed for $set"
    [[ "$actual" == "$expected" ]] || fail "UAF mapping mismatch for $set: expected $expected, got $actual"
  done
}

model_bytes() {
  local set="$1" out
  out="$($HELPER bytes "$set" 2>/dev/null)" || return 1
  [[ "$out" =~ ^[0-9]+$ ]] || return 1
  printf '%s' "$out"
}

format_bytes() {
  local b="$1"
  if (( b >= 1000000000 )); then awk -v n="$b" 'BEGIN { printf "%.1f GB", n/1e9 }'
  elif (( b > 0 )); then awk -v n="$b" 'BEGIN { printf "%.0f MB", n/1e6 }'
  else echo '0 MB'; fi
}

feature_state() {
  local feature="$1" domain key want output forced value
  local all=1 any=0
  while IFS=$'\t' read -r domain key want; do
    [[ -n "$domain" ]] || continue
    output="$(helper_pref "$domain" "$key" 2>/dev/null)" || { echo unknown; return; }
    forced="$(printf '%s' "$output" | sed -n 's/.*forced=\([^\t]*\).*/\1/p')"
    value="$(printf '%s' "$output" | sed -n 's/.*value=\([^\t]*\)$/\1/p')"
    [[ "$forced" == 1 && "$value" == "$want" ]] && any=1 || all=0
  done < <(feature_preferences "$feature")
  if (( all == 1 && any == 1 )); then echo locked; return; fi

  case "$feature" in
    chatgpt|writing-tools|genmoji|image-playground|safari-summaries|notes-summaries)
      local restricted_ok=1 r
      while IFS= read -r r; do
        [[ -n "$r" ]] || continue
        output="$(helper_pref com.apple.applicationaccess "$r" 2>/dev/null)" || { echo unknown; return; }
        [[ "$output" == *$'forced=1\tvalue=false'* ]] || restricted_ok=0
      done < <(feature_restrictions "$feature")
      (( restricted_ok == 1 )) && echo locked && return
      ;;
  esac

  if profile_installed && ! kept "$feature" && [[ -z "$(feature_preferences "$feature")" ]] && [[ -z "$(feature_restrictions "$feature")" ]]; then
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
  local feature state set n total=0
  for feature in "${FEATURES[@]}"; do
    state="$(feature_state "$feature")"
    printf '%-44s %s\n' "$(feature_title "$feature")" "$state"
  done
  printf '\nModels on disk\n'
  for set in "${MODEL_SETS[@]}"; do
    if n="$(model_bytes "$set")"; then
      total=$((total+n)); printf '  %-44s %s\n' "$(model_set_title "$set")" "$(format_bytes "$n")"
    else
      printf '  %-44s unknown\n' "$(model_set_title "$set")"
    fi
  done
  printf '  %-44s %s\n' Total "$(format_bytes "$total")"
  printf 'Profile: %s\n' "$(profile_installed && echo installed || echo not-installed)"
}

print_features() {
  local f
  for f in "${FEATURES[@]}"; do printf '%-28s %s\n' "$f" "$(feature_title "$f")"; done
}

open_profile_settings() {
  open 'x-apple.systempreferences:com.apple.Profiles-Settings.extension' 2>/dev/null || open 'x-apple.systempreferences:com.apple.preferences.configurationprofiles' 2>/dev/null || true
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
  printf 'Turn off Apple Intelligence and reset the selected models? [y/N] '
  read -r answer
  [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

off_command() {
  parse_args "$@"
  build_helper
  legacy_profile_installed && fail "legacy RemoveMacAI profile is installed; run '$0 revert' first"
  validate_uaf_catalog
  local sets
  sets="$(sets_to_remove)"

  printf 'Features to disable:\n'
  local f
  for f in "${FEATURES[@]}"; do kept "$f" || printf '  - %s\n' "$(feature_title "$f")"; done
  printf 'Model sets to reset:\n%s\n' "$(printf '%s\n' "$sets" | sed 's/^/  - /')"

  if (( DRY_RUN == 1 )); then
    local dry="${TMPDIR:-/tmp}/Apple-AI-remover.$$.mobileconfig"
    build_profile "$dry" "$sets"
    info 'DRY RUN: no profile was installed and no model was reset.'
    info "generated profile: $dry"
    return 0
  fi

  confirm || { info 'Nothing changed.'; return 0; }

  local expected
  expected="$(keep_csv)"
  build_profile "$PROFILE_FILE" "$sets"
  open "$PROFILE_FILE" 2>/dev/null || true
  open_profile_settings
  info "Approve '$PROFILE_NAME' in System Settings."
  wait_for_profile "$expected" || fail 'profile installation was not observed; no model reset was attempted'

  if [[ -n "$sets" ]]; then
    if reset_models "$sets"; then
      info 'All selected model sets reset successfully.'
    else
      fail 'profile is installed, but one or more model resets failed; run status to inspect remaining model state'
    fi
  fi
  info "Done. Run: $0 status"
}

revert_command() {
  build_helper
  local current=0 legacy=0
  profile_installed && current=1
  legacy_profile_installed && legacy=1
  if (( current == 0 && legacy == 0 )); then info 'No Apple AI remover profile is installed.'; return 0; fi
  if (( YES == 0 )); then
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
  local f set x saved_keep all a b
  for f in "${FEATURES[@]}"; do
    feature_title "$f" >/dev/null || fail "missing title for $f"
    while IFS= read -r x; do
      [[ -z "$x" ]] && continue
      model_set_asset_type "$x" >/dev/null || fail "unknown model set $x referenced by $f"
    done < <(feature_model_sets "$f")
  done
  for set in "${MODEL_SETS[@]}"; do model_set_asset_type "$set" >/dev/null || fail "missing model-set mapping $set"; done

  saved_keep=("${KEEP[@]}")
  KEEP=()
  all="$(sets_to_remove)"
  [[ "$(printf '%s\n' "$all" | sort)" == "$(printf '%s\n' "${MODEL_SETS[@]}" | sort)" ]] || fail 'empty keep set must remove every model set'

  KEEP=(writing-tools)
  all="$(sets_to_remove)"
  ! grep -qx 'com.apple.modelcatalog' <<< "$all" || fail 'writing-tools must protect foundation models'
  grep -qx 'com.apple.MobileAsset.UAF.FM.Visual' <<< "$all" || fail 'writing-tools unexpectedly protects visual models'
  KEEP=("${saved_keep[@]}")

  a="$(stable_uuid "$PROFILE_ID")"; b="$(stable_uuid "$PROFILE_ID")"; [[ "$a" == "$b" ]] || fail 'payload UUID generator is not stable'
  printf 'selftest: PASS (%s features, %s model sets)\n' "${#FEATURES[@]}" "${#MODEL_SETS[@]}"
}

usage() {
  cat <<EOF_USAGE
$PRODUCT_NAME $VERSION

Usage:
  $0 status
  $0 features
  $0 off [--keep feature[,feature...]] [--dry-run] [--yes]
  $0 revert [--yes]
  $0 selftest

The mutating commands target macOS $TARGET_MAJOR.x on Apple silicon.
EOF_USAGE
}

main() {
  local command="${1:-status}"
  shift || true
  case "$command" in
    status) require_platform; status_command "$@" ;;
    features) [[ "$#" -eq 0 ]] || fail 'features takes no options'; print_features ;;
    off) require_platform; off_command "$@" ;;
    revert) require_platform; parse_args "$@"; revert_command ;;
    selftest) [[ "$#" -eq 0 ]] || fail 'selftest takes no options'; selftest_command ;;
    --help|-h|help) usage ;;
    --version|-v|version) echo "$VERSION" ;;
    *) usage >&2; exit 1 ;;
  esac
}

main "$@"
forced=1\tvalue=true'* ]]; }
profile_kept_csv() { local o; o="$(helper_pref "$PROFILE_ID" kept 2>/dev/null)" || return 1; printf '%s' "${o#*value=}"; }

validate_uaf_catalog() {
  local set expected actual
  for set in "${MODEL_SETS[@]}"; do
    expected="$(model_set_asset_type "$set")"
    actual="$($HELPER asset-type "$set")" || fail "UAF asset-set lookup failed for $set"
    [[ "$actual" == "$expected" ]] || fail "UAF mapping mismatch for $set: expected $expected, got $actual"
  done
}

model_bytes() {
  local set="$1" out
  out="$($HELPER bytes "$set" 2>/dev/null)" || return 1
  [[ "$out" =~ ^[0-9]+$ ]] || return 1
  printf '%s' "$out"
}

format_bytes() {
  local b="$1"
  if (( b >= 1000000000 )); then awk -v n="$b" 'BEGIN { printf "%.1f GB", n/1e9 }'
  elif (( b > 0 )); then awk -v n="$b" 'BEGIN { printf "%.0f MB", n/1e6 }'
  else echo '0 MB'; fi
}

feature_state() {
  local feature="$1" domain key want output forced value
  local all=1 any=0
  while IFS=$'\t' read -r domain key want; do
    [[ -n "$domain" ]] || continue
    output="$(helper_pref "$domain" "$key" 2>/dev/null)" || { echo unknown; return; }
    forced="$(printf '%s' "$output" | sed -n 's/.*forced=\([^\t]*\).*/\1/p')"
    value="$(printf '%s' "$output" | sed -n 's/.*value=\([^\t]*\)$/\1/p')"
    [[ "$forced" == 1 && "$value" == "$want" ]] && any=1 || all=0
  done < <(feature_preferences "$feature")
  if (( all == 1 && any == 1 )); then echo locked; return; fi

  case "$feature" in
    chatgpt|writing-tools|genmoji|image-playground|safari-summaries|notes-summaries)
      local restricted_ok=1 r
      while IFS= read -r r; do
        [[ -n "$r" ]] || continue
        output="$(helper_pref com.apple.applicationaccess "$r" 2>/dev/null)" || { echo unknown; return; }
        [[ "$output" == *$'forced=1\tvalue=false'* ]] || restricted_ok=0
      done < <(feature_restrictions "$feature")
      (( restricted_ok == 1 )) && echo locked && return
      ;;
  esac

  if profile_installed && ! kept "$feature" && [[ -z "$(feature_preferences "$feature")" ]] && [[ -z "$(feature_restrictions "$feature")" ]]; then
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
  local feature state set n total=0
  for feature in "${FEATURES[@]}"; do
    state="$(feature_state "$feature")"
    printf '%-44s %s\n' "$(feature_title "$feature")" "$state"
  done
  printf '\nModels on disk\n'
  for set in "${MODEL_SETS[@]}"; do
    if n="$(model_bytes "$set")"; then
      total=$((total+n)); printf '  %-44s %s\n' "$(model_set_title "$set")" "$(format_bytes "$n")"
    else
      printf '  %-44s unknown\n' "$(model_set_title "$set")"
    fi
  done
  printf '  %-44s %s\n' Total "$(format_bytes "$total")"
  printf 'Profile: %s\n' "$(profile_installed && echo installed || echo not-installed)"
}

print_features() {
  local f
  for f in "${FEATURES[@]}"; do printf '%-28s %s\n' "$f" "$(feature_title "$f")"; done
}

open_profile_settings() {
  open 'x-apple.systempreferences:com.apple.Profiles-Settings.extension' 2>/dev/null || open 'x-apple.systempreferences:com.apple.preferences.configurationprofiles' 2>/dev/null || true
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
  printf 'Turn off Apple Intelligence and reset the selected models? [y/N] '
  read -r answer
  [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

off_command() {
  parse_args "$@"
  build_helper
  legacy_profile_installed && fail "legacy RemoveMacAI profile is installed; run '$0 revert' first"
  validate_uaf_catalog
  local sets
  sets="$(sets_to_remove)"

  printf 'Features to disable:\n'
  local f
  for f in "${FEATURES[@]}"; do kept "$f" || printf '  - %s\n' "$(feature_title "$f")"; done
  printf 'Model sets to reset:\n%s\n' "$(printf '%s\n' "$sets" | sed 's/^/  - /')"

  if (( DRY_RUN == 1 )); then
    local dry="${TMPDIR:-/tmp}/Apple-AI-remover.$$.mobileconfig"
    build_profile "$dry" "$sets"
    info 'DRY RUN: no profile was installed and no model was reset.'
    info "generated profile: $dry"
    return 0
  fi

  confirm || { info 'Nothing changed.'; return 0; }

  local expected
  expected="$(keep_csv)"
  build_profile "$PROFILE_FILE" "$sets"
  open "$PROFILE_FILE" 2>/dev/null || true
  open_profile_settings
  info "Approve '$PROFILE_NAME' in System Settings."
  wait_for_profile "$expected" || fail 'profile installation was not observed; no model reset was attempted'

  if [[ -n "$sets" ]]; then
    if reset_models "$sets"; then
      info 'All selected model sets reset successfully.'
    else
      fail 'profile is installed, but one or more model resets failed; run status to inspect remaining model state'
    fi
  fi
  info "Done. Run: $0 status"
}

revert_command() {
  build_helper
  local current=0 legacy=0
  profile_installed && current=1
  legacy_profile_installed && legacy=1
  if (( current == 0 && legacy == 0 )); then info 'No Apple AI remover profile is installed.'; return 0; fi
  if (( YES == 0 )); then
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
  local f set x saved_keep all a b
  for f in "${FEATURES[@]}"; do
    feature_title "$f" >/dev/null || fail "missing title for $f"
    while IFS= read -r x; do
      [[ -z "$x" ]] && continue
      model_set_asset_type "$x" >/dev/null || fail "unknown model set $x referenced by $f"
    done < <(feature_model_sets "$f")
  done
  for set in "${MODEL_SETS[@]}"; do model_set_asset_type "$set" >/dev/null || fail "missing model-set mapping $set"; done

  saved_keep=("${KEEP[@]}")
  KEEP=()
  all="$(sets_to_remove)"
  [[ "$(printf '%s\n' "$all" | sort)" == "$(printf '%s\n' "${MODEL_SETS[@]}" | sort)" ]] || fail 'empty keep set must remove every model set'

  KEEP=(writing-tools)
  all="$(sets_to_remove)"
  ! grep -qx 'com.apple.modelcatalog' <<< "$all" || fail 'writing-tools must protect foundation models'
  grep -qx 'com.apple.MobileAsset.UAF.FM.Visual' <<< "$all" || fail 'writing-tools unexpectedly protects visual models'
  KEEP=("${saved_keep[@]}")

  a="$(stable_uuid "$PROFILE_ID")"; b="$(stable_uuid "$PROFILE_ID")"; [[ "$a" == "$b" ]] || fail 'payload UUID generator is not stable'
  printf 'selftest: PASS (%s features, %s model sets)\n' "${#FEATURES[@]}" "${#MODEL_SETS[@]}"
}

usage() {
  cat <<EOF_USAGE
$PRODUCT_NAME $VERSION

Usage:
  $0 status
  $0 features
  $0 off [--keep feature[,feature...]] [--dry-run] [--yes]
  $0 revert [--yes]
  $0 selftest

The mutating commands target macOS $TARGET_MAJOR.x on Apple silicon.
EOF_USAGE
}

main() {
  local command="${1:-status}"
  shift || true
  case "$command" in
    status) require_platform; status_command "$@" ;;
    features) [[ "$#" -eq 0 ]] || fail 'features takes no options'; print_features ;;
    off) require_platform; off_command "$@" ;;
    revert) require_platform; parse_args "$@"; revert_command ;;
    selftest) [[ "$#" -eq 0 ]] || fail 'selftest takes no options'; selftest_command ;;
    --help|-h|help) usage ;;
    --version|-v|version) echo "$VERSION" ;;
    *) usage >&2; exit 1 ;;
  esac
}

main "$@"
\t'"${key}"
    [[ -n "$set" ]] || continue
    key="DownloadServerBaseURLOverride-$(model_set_asset_type "$set")"
    PREF_LINES="${PREF_LINES}com.apple.MobileAsset"$'\t'"${key}"$'\t'"${BLOCKED_URL}"$'\n'
  done <<< "$sets"

  mkdir -p "$(dirname "$output")"
  {
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
    printf '%s\n' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    printf '%s\n' '<plist version="1.0"><dict>'
    printf '%s\n' '<key>PayloadType</key><string>Configuration</string>'
    printf '%s\n' '<key>PayloadVersion</key><integer>1</integer>'
    printf '<key>PayloadIdentifier</key><string>%s</string>\n' "$PROFILE_ID"
    printf '<key>PayloadUUID</key><string>%s</string>\n' "$(stable_uuid "$PROFILE_ID")"
    printf '<key>PayloadDisplayName</key><string>%s</string>\n' "$(xml_escape "$PROFILE_NAME")"
    printf '%s\n' '<key>PayloadDescription</key><string>Disables Apple Intelligence features and prevents selected model sets from being re-downloaded. Remove this profile to undo.</string>'
    printf '%s\n' '<key>PayloadOrganization</key><string>Apple AI remover</string>'
    printf '%s\n' '<key>PayloadScope</key><string>System</string>'
    printf '%s\n' '<key>PayloadRemovalDisallowed</key><false/>'
    printf '%s\n' '<key>PayloadContent</key><array>'

    payload_header com.apple.applicationaccess restrictions 'Apple Intelligence restrictions'
    printf '%s\n' '      <key>PayloadContent</key><dict>'
    for feature in "${FEATURES[@]}"; do
      kept "$feature" && continue
      while IFS= read -r key; do
        [[ -n "$key" ]] && printf '        <key>%s</key><false/>\n' "$(xml_escape "$key")"
      done < <(feature_restrictions "$feature")
    done
    printf '%s\n' '      </dict>' '    </dict>'

    for d in com.apple.assistant.support com.apple.Siri group.com.apple.mail group.com.apple.usernoted com.apple.MobileSMS .GlobalPreferences com.apple.spatialphotosrelive; do
      PREF_LINES=''
      while IFS=$'\t' read -r domain key value; do
        [[ "$domain" == "$d" ]] || continue
        PREF_LINES="${PREF_LINES}${key}"$'\t'"${value}"$'\n'
      done <<< "$ALL_PREFS"
      append_pref_payload "$d" "$d" "Forced settings: $d"
    done

    PREF_LINES=''
    while IFS=$'\t' read -r domain key value; do
      [[ "$domain" == 'com.apple.MobileAsset' ]] || continue
      PREF_LINES="${PREF_LINES}${key}"$'\t'"${value}"$'\n'
    done <<< "$ALL_PREFS"
    append_pref_payload com.apple.MobileAsset MobileAsset 'MobileAsset download overrides'

    PREF_LINES="installed"$'\t'true$'\n'"kept"$'\t'"$(keep_csv)"$'\n'
    append_pref_payload "$PROFILE_ID" marker 'Apple AI remover state'

    printf '%s\n' '</array></dict></plist>'
  } > "$tmp"
  /usr/bin/plutil -lint "$tmp" >/dev/null 2>&1 || { rm -f "$tmp"; fail 'generated profile failed plist validation'; }
  mv "$tmp" "$output"
}

keep_csv() {
  local out='' item
  for item in "${KEEP[@]}"; do
    [[ -n "$out" ]] && out="$out,"
    out="$out$item"
  done
  printf '%s' "$out"
}

helper_pref() { "$HELPER" pref "$1" "$2"; }
profile_installed() { local o; o="$(helper_pref "$PROFILE_ID" installed 2>/dev/null)" || return 1; [[ "$o" == *$'forced=1\tvalue=true'* ]]; }
legacy_profile_installed() { local o; o="$(helper_pref "$LEGACY_PROFILE_ID" installed 2>/dev/null)" || return 1; [[ "$o" == *$'forced=1\tvalue=true'* ]]; }
profile_kept_csv() { local o; o="$(helper_pref "$PROFILE_ID" kept 2>/dev/null)" || return 1; printf '%s' "${o#*value=}"; }

validate_uaf_catalog() {
  local set expected actual
  for set in "${MODEL_SETS[@]}"; do
    expected="$(model_set_asset_type "$set")"
    actual="$($HELPER asset-type "$set")" || fail "UAF asset-set lookup failed for $set"
    [[ "$actual" == "$expected" ]] || fail "UAF mapping mismatch for $set: expected $expected, got $actual"
  done
}

model_bytes() {
  local set="$1" out
  out="$($HELPER bytes "$set" 2>/dev/null)" || return 1
  [[ "$out" =~ ^[0-9]+$ ]] || return 1
  printf '%s' "$out"
}

format_bytes() {
  local b="$1"
  if (( b >= 1000000000 )); then awk -v n="$b" 'BEGIN { printf "%.1f GB", n/1e9 }'
  elif (( b > 0 )); then awk -v n="$b" 'BEGIN { printf "%.0f MB", n/1e6 }'
  else echo '0 MB'; fi
}

feature_state() {
  local feature="$1" domain key want output forced value
  local all=1 any=0
  while IFS=$'\t' read -r domain key want; do
    [[ -n "$domain" ]] || continue
    output="$(helper_pref "$domain" "$key" 2>/dev/null)" || { echo unknown; return; }
    forced="$(printf '%s' "$output" | sed -n 's/.*forced=\([^\t]*\).*/\1/p')"
    value="$(printf '%s' "$output" | sed -n 's/.*value=\([^\t]*\)$/\1/p')"
    [[ "$forced" == 1 && "$value" == "$want" ]] && any=1 || all=0
  done < <(feature_preferences "$feature")
  if (( all == 1 && any == 1 )); then echo locked; return; fi

  case "$feature" in
    chatgpt|writing-tools|genmoji|image-playground|safari-summaries|notes-summaries)
      local restricted_ok=1 r
      while IFS= read -r r; do
        [[ -n "$r" ]] || continue
        output="$(helper_pref com.apple.applicationaccess "$r" 2>/dev/null)" || { echo unknown; return; }
        [[ "$output" == *$'forced=1\tvalue=false'* ]] || restricted_ok=0
      done < <(feature_restrictions "$feature")
      (( restricted_ok == 1 )) && echo locked && return
      ;;
  esac

  if profile_installed && ! kept "$feature" && [[ -z "$(feature_preferences "$feature")" ]] && [[ -z "$(feature_restrictions "$feature")" ]]; then
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
  local feature state set n total=0
  for feature in "${FEATURES[@]}"; do
    state="$(feature_state "$feature")"
    printf '%-44s %s\n' "$(feature_title "$feature")" "$state"
  done
  printf '\nModels on disk\n'
  for set in "${MODEL_SETS[@]}"; do
    if n="$(model_bytes "$set")"; then
      total=$((total+n)); printf '  %-44s %s\n' "$(model_set_title "$set")" "$(format_bytes "$n")"
    else
      printf '  %-44s unknown\n' "$(model_set_title "$set")"
    fi
  done
  printf '  %-44s %s\n' Total "$(format_bytes "$total")"
  printf 'Profile: %s\n' "$(profile_installed && echo installed || echo not-installed)"
}

print_features() {
  local f
  for f in "${FEATURES[@]}"; do printf '%-28s %s\n' "$f" "$(feature_title "$f")"; done
}

open_profile_settings() {
  open 'x-apple.systempreferences:com.apple.Profiles-Settings.extension' 2>/dev/null || open 'x-apple.systempreferences:com.apple.preferences.configurationprofiles' 2>/dev/null || true
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
  printf 'Turn off Apple Intelligence and reset the selected models? [y/N] '
  read -r answer
  [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

off_command() {
  parse_args "$@"
  build_helper
  legacy_profile_installed && fail "legacy RemoveMacAI profile is installed; run '$0 revert' first"
  validate_uaf_catalog
  local sets
  sets="$(sets_to_remove)"

  printf 'Features to disable:\n'
  local f
  for f in "${FEATURES[@]}"; do kept "$f" || printf '  - %s\n' "$(feature_title "$f")"; done
  printf 'Model sets to reset:\n%s\n' "$(printf '%s\n' "$sets" | sed 's/^/  - /')"

  if (( DRY_RUN == 1 )); then
    local dry="${TMPDIR:-/tmp}/Apple-AI-remover.$$.mobileconfig"
    build_profile "$dry" "$sets"
    info 'DRY RUN: no profile was installed and no model was reset.'
    info "generated profile: $dry"
    return 0
  fi

  confirm || { info 'Nothing changed.'; return 0; }

  local expected
  expected="$(keep_csv)"
  build_profile "$PROFILE_FILE" "$sets"
  open "$PROFILE_FILE" 2>/dev/null || true
  open_profile_settings
  info "Approve '$PROFILE_NAME' in System Settings."
  wait_for_profile "$expected" || fail 'profile installation was not observed; no model reset was attempted'

  if [[ -n "$sets" ]]; then
    if reset_models "$sets"; then
      info 'All selected model sets reset successfully.'
    else
      fail 'profile is installed, but one or more model resets failed; run status to inspect remaining model state'
    fi
  fi
  info "Done. Run: $0 status"
}

revert_command() {
  build_helper
  local current=0 legacy=0
  profile_installed && current=1
  legacy_profile_installed && legacy=1
  if (( current == 0 && legacy == 0 )); then info 'No Apple AI remover profile is installed.'; return 0; fi
  if (( YES == 0 )); then
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
  local f set x saved_keep all a b
  for f in "${FEATURES[@]}"; do
    feature_title "$f" >/dev/null || fail "missing title for $f"
    while IFS= read -r x; do
      [[ -z "$x" ]] && continue
      model_set_asset_type "$x" >/dev/null || fail "unknown model set $x referenced by $f"
    done < <(feature_model_sets "$f")
  done
  for set in "${MODEL_SETS[@]}"; do model_set_asset_type "$set" >/dev/null || fail "missing model-set mapping $set"; done

  saved_keep=("${KEEP[@]}")
  KEEP=()
  all="$(sets_to_remove)"
  [[ "$(printf '%s\n' "$all" | sort)" == "$(printf '%s\n' "${MODEL_SETS[@]}" | sort)" ]] || fail 'empty keep set must remove every model set'

  KEEP=(writing-tools)
  all="$(sets_to_remove)"
  ! grep -qx 'com.apple.modelcatalog' <<< "$all" || fail 'writing-tools must protect foundation models'
  grep -qx 'com.apple.MobileAsset.UAF.FM.Visual' <<< "$all" || fail 'writing-tools unexpectedly protects visual models'
  KEEP=("${saved_keep[@]}")

  a="$(stable_uuid "$PROFILE_ID")"; b="$(stable_uuid "$PROFILE_ID")"; [[ "$a" == "$b" ]] || fail 'payload UUID generator is not stable'
  printf 'selftest: PASS (%s features, %s model sets)\n' "${#FEATURES[@]}" "${#MODEL_SETS[@]}"
}

usage() {
  cat <<EOF_USAGE
$PRODUCT_NAME $VERSION

Usage:
  $0 status
  $0 features
  $0 off [--keep feature[,feature...]] [--dry-run] [--yes]
  $0 revert [--yes]
  $0 selftest

The mutating commands target macOS $TARGET_MAJOR.x on Apple silicon.
EOF_USAGE
}

main() {
  local command="${1:-status}"
  shift || true
  case "$command" in
    status) require_platform; status_command "$@" ;;
    features) [[ "$#" -eq 0 ]] || fail 'features takes no options'; print_features ;;
    off) require_platform; off_command "$@" ;;
    revert) require_platform; parse_args "$@"; revert_command ;;
    selftest) [[ "$#" -eq 0 ]] || fail 'selftest takes no options'; selftest_command ;;
    --help|-h|help) usage ;;
    --version|-v|version) echo "$VERSION" ;;
    *) usage >&2; exit 1 ;;
  esac
}

main "$@"
\t'"${value}"
    [[ -n "$set" ]] || continue
    key="DownloadServerBaseURLOverride-$(model_set_asset_type "$set")"
    PREF_LINES="${PREF_LINES}com.apple.MobileAsset"$'\t'"${key}"$'\t'"${BLOCKED_URL}"$'\n'
  done <<< "$sets"

  mkdir -p "$(dirname "$output")"
  {
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
    printf '%s\n' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    printf '%s\n' '<plist version="1.0"><dict>'
    printf '%s\n' '<key>PayloadType</key><string>Configuration</string>'
    printf '%s\n' '<key>PayloadVersion</key><integer>1</integer>'
    printf '<key>PayloadIdentifier</key><string>%s</string>\n' "$PROFILE_ID"
    printf '<key>PayloadUUID</key><string>%s</string>\n' "$(stable_uuid "$PROFILE_ID")"
    printf '<key>PayloadDisplayName</key><string>%s</string>\n' "$(xml_escape "$PROFILE_NAME")"
    printf '%s\n' '<key>PayloadDescription</key><string>Disables Apple Intelligence features and prevents selected model sets from being re-downloaded. Remove this profile to undo.</string>'
    printf '%s\n' '<key>PayloadOrganization</key><string>Apple AI remover</string>'
    printf '%s\n' '<key>PayloadScope</key><string>System</string>'
    printf '%s\n' '<key>PayloadRemovalDisallowed</key><false/>'
    printf '%s\n' '<key>PayloadContent</key><array>'

    payload_header com.apple.applicationaccess restrictions 'Apple Intelligence restrictions'
    printf '%s\n' '      <key>PayloadContent</key><dict>'
    for feature in "${FEATURES[@]}"; do
      kept "$feature" && continue
      while IFS= read -r key; do
        [[ -n "$key" ]] && printf '        <key>%s</key><false/>\n' "$(xml_escape "$key")"
      done < <(feature_restrictions "$feature")
    done
    printf '%s\n' '      </dict>' '    </dict>'

    for d in com.apple.assistant.support com.apple.Siri group.com.apple.mail group.com.apple.usernoted com.apple.MobileSMS .GlobalPreferences com.apple.spatialphotosrelive; do
      PREF_LINES=''
      while IFS=$'\t' read -r domain key value; do
        [[ "$domain" == "$d" ]] || continue
        PREF_LINES="${PREF_LINES}${key}"$'\t'"${value}"$'\n'
      done <<< "$ALL_PREFS"
      append_pref_payload "$d" "$d" "Forced settings: $d"
    done

    PREF_LINES=''
    while IFS=$'\t' read -r domain key value; do
      [[ "$domain" == 'com.apple.MobileAsset' ]] || continue
      PREF_LINES="${PREF_LINES}${key}"$'\t'"${value}"$'\n'
    done <<< "$ALL_PREFS"
    append_pref_payload com.apple.MobileAsset MobileAsset 'MobileAsset download overrides'

    PREF_LINES="installed"$'\t'true$'\n'"kept"$'\t'"$(keep_csv)"$'\n'
    append_pref_payload "$PROFILE_ID" marker 'Apple AI remover state'

    printf '%s\n' '</array></dict></plist>'
  } > "$tmp"
  /usr/bin/plutil -lint "$tmp" >/dev/null 2>&1 || { rm -f "$tmp"; fail 'generated profile failed plist validation'; }
  mv "$tmp" "$output"
}

keep_csv() {
  local out='' item
  for item in "${KEEP[@]}"; do
    [[ -n "$out" ]] && out="$out,"
    out="$out$item"
  done
  printf '%s' "$out"
}

helper_pref() { "$HELPER" pref "$1" "$2"; }
profile_installed() { local o; o="$(helper_pref "$PROFILE_ID" installed 2>/dev/null)" || return 1; [[ "$o" == *$'forced=1\tvalue=true'* ]]; }
legacy_profile_installed() { local o; o="$(helper_pref "$LEGACY_PROFILE_ID" installed 2>/dev/null)" || return 1; [[ "$o" == *$'forced=1\tvalue=true'* ]]; }
profile_kept_csv() { local o; o="$(helper_pref "$PROFILE_ID" kept 2>/dev/null)" || return 1; printf '%s' "${o#*value=}"; }

validate_uaf_catalog() {
  local set expected actual
  for set in "${MODEL_SETS[@]}"; do
    expected="$(model_set_asset_type "$set")"
    actual="$($HELPER asset-type "$set")" || fail "UAF asset-set lookup failed for $set"
    [[ "$actual" == "$expected" ]] || fail "UAF mapping mismatch for $set: expected $expected, got $actual"
  done
}

model_bytes() {
  local set="$1" out
  out="$($HELPER bytes "$set" 2>/dev/null)" || return 1
  [[ "$out" =~ ^[0-9]+$ ]] || return 1
  printf '%s' "$out"
}

format_bytes() {
  local b="$1"
  if (( b >= 1000000000 )); then awk -v n="$b" 'BEGIN { printf "%.1f GB", n/1e9 }'
  elif (( b > 0 )); then awk -v n="$b" 'BEGIN { printf "%.0f MB", n/1e6 }'
  else echo '0 MB'; fi
}

feature_state() {
  local feature="$1" domain key want output forced value
  local all=1 any=0
  while IFS=$'\t' read -r domain key want; do
    [[ -n "$domain" ]] || continue
    output="$(helper_pref "$domain" "$key" 2>/dev/null)" || { echo unknown; return; }
    forced="$(printf '%s' "$output" | sed -n 's/.*forced=\([^\t]*\).*/\1/p')"
    value="$(printf '%s' "$output" | sed -n 's/.*value=\([^\t]*\)$/\1/p')"
    [[ "$forced" == 1 && "$value" == "$want" ]] && any=1 || all=0
  done < <(feature_preferences "$feature")
  if (( all == 1 && any == 1 )); then echo locked; return; fi

  case "$feature" in
    chatgpt|writing-tools|genmoji|image-playground|safari-summaries|notes-summaries)
      local restricted_ok=1 r
      while IFS= read -r r; do
        [[ -n "$r" ]] || continue
        output="$(helper_pref com.apple.applicationaccess "$r" 2>/dev/null)" || { echo unknown; return; }
        [[ "$output" == *$'forced=1\tvalue=false'* ]] || restricted_ok=0
      done < <(feature_restrictions "$feature")
      (( restricted_ok == 1 )) && echo locked && return
      ;;
  esac

  if profile_installed && ! kept "$feature" && [[ -z "$(feature_preferences "$feature")" ]] && [[ -z "$(feature_restrictions "$feature")" ]]; then
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
  local feature state set n total=0
  for feature in "${FEATURES[@]}"; do
    state="$(feature_state "$feature")"
    printf '%-44s %s\n' "$(feature_title "$feature")" "$state"
  done
  printf '\nModels on disk\n'
  for set in "${MODEL_SETS[@]}"; do
    if n="$(model_bytes "$set")"; then
      total=$((total+n)); printf '  %-44s %s\n' "$(model_set_title "$set")" "$(format_bytes "$n")"
    else
      printf '  %-44s unknown\n' "$(model_set_title "$set")"
    fi
  done
  printf '  %-44s %s\n' Total "$(format_bytes "$total")"
  printf 'Profile: %s\n' "$(profile_installed && echo installed || echo not-installed)"
}

print_features() {
  local f
  for f in "${FEATURES[@]}"; do printf '%-28s %s\n' "$f" "$(feature_title "$f")"; done
}

open_profile_settings() {
  open 'x-apple.systempreferences:com.apple.Profiles-Settings.extension' 2>/dev/null || open 'x-apple.systempreferences:com.apple.preferences.configurationprofiles' 2>/dev/null || true
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
  printf 'Turn off Apple Intelligence and reset the selected models? [y/N] '
  read -r answer
  [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

off_command() {
  parse_args "$@"
  build_helper
  legacy_profile_installed && fail "legacy RemoveMacAI profile is installed; run '$0 revert' first"
  validate_uaf_catalog
  local sets
  sets="$(sets_to_remove)"

  printf 'Features to disable:\n'
  local f
  for f in "${FEATURES[@]}"; do kept "$f" || printf '  - %s\n' "$(feature_title "$f")"; done
  printf 'Model sets to reset:\n%s\n' "$(printf '%s\n' "$sets" | sed 's/^/  - /')"

  if (( DRY_RUN == 1 )); then
    local dry="${TMPDIR:-/tmp}/Apple-AI-remover.$$.mobileconfig"
    build_profile "$dry" "$sets"
    info 'DRY RUN: no profile was installed and no model was reset.'
    info "generated profile: $dry"
    return 0
  fi

  confirm || { info 'Nothing changed.'; return 0; }

  local expected
  expected="$(keep_csv)"
  build_profile "$PROFILE_FILE" "$sets"
  open "$PROFILE_FILE" 2>/dev/null || true
  open_profile_settings
  info "Approve '$PROFILE_NAME' in System Settings."
  wait_for_profile "$expected" || fail 'profile installation was not observed; no model reset was attempted'

  if [[ -n "$sets" ]]; then
    if reset_models "$sets"; then
      info 'All selected model sets reset successfully.'
    else
      fail 'profile is installed, but one or more model resets failed; run status to inspect remaining model state'
    fi
  fi
  info "Done. Run: $0 status"
}

revert_command() {
  build_helper
  local current=0 legacy=0
  profile_installed && current=1
  legacy_profile_installed && legacy=1
  if (( current == 0 && legacy == 0 )); then info 'No Apple AI remover profile is installed.'; return 0; fi
  if (( YES == 0 )); then
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
  local f set x saved_keep all a b
  for f in "${FEATURES[@]}"; do
    feature_title "$f" >/dev/null || fail "missing title for $f"
    while IFS= read -r x; do
      [[ -z "$x" ]] && continue
      model_set_asset_type "$x" >/dev/null || fail "unknown model set $x referenced by $f"
    done < <(feature_model_sets "$f")
  done
  for set in "${MODEL_SETS[@]}"; do model_set_asset_type "$set" >/dev/null || fail "missing model-set mapping $set"; done

  saved_keep=("${KEEP[@]}")
  KEEP=()
  all="$(sets_to_remove)"
  [[ "$(printf '%s\n' "$all" | sort)" == "$(printf '%s\n' "${MODEL_SETS[@]}" | sort)" ]] || fail 'empty keep set must remove every model set'

  KEEP=(writing-tools)
  all="$(sets_to_remove)"
  ! grep -qx 'com.apple.modelcatalog' <<< "$all" || fail 'writing-tools must protect foundation models'
  grep -qx 'com.apple.MobileAsset.UAF.FM.Visual' <<< "$all" || fail 'writing-tools unexpectedly protects visual models'
  KEEP=("${saved_keep[@]}")

  a="$(stable_uuid "$PROFILE_ID")"; b="$(stable_uuid "$PROFILE_ID")"; [[ "$a" == "$b" ]] || fail 'payload UUID generator is not stable'
  printf 'selftest: PASS (%s features, %s model sets)\n' "${#FEATURES[@]}" "${#MODEL_SETS[@]}"
}

usage() {
  cat <<EOF_USAGE
$PRODUCT_NAME $VERSION

Usage:
  $0 status
  $0 features
  $0 off [--keep feature[,feature...]] [--dry-run] [--yes]
  $0 revert [--yes]
  $0 selftest

The mutating commands target macOS $TARGET_MAJOR.x on Apple silicon.
EOF_USAGE
}

main() {
  local command="${1:-status}"
  shift || true
  case "$command" in
    status) require_platform; status_command "$@" ;;
    features) [[ "$#" -eq 0 ]] || fail 'features takes no options'; print_features ;;
    off) require_platform; off_command "$@" ;;
    revert) require_platform; parse_args "$@"; revert_command ;;
    selftest) [[ "$#" -eq 0 ]] || fail 'selftest takes no options'; selftest_command ;;
    --help|-h|help) usage ;;
    --version|-v|version) echo "$VERSION" ;;
    *) usage >&2; exit 1 ;;
  esac
}

main "$@"
\n'
    done < <(feature_preferences "$feature")
  done
  while IFS= read -r set; do
    [[ -n "$set" ]] || continue
    key="DownloadServerBaseURLOverride-$(model_set_asset_type "$set")"
    PREF_LINES="${PREF_LINES}com.apple.MobileAsset"$'\t'"${key}"$'\t'"${BLOCKED_URL}"$'\n'
  done <<< "$sets"

  mkdir -p "$(dirname "$output")"
  {
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
    printf '%s\n' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    printf '%s\n' '<plist version="1.0"><dict>'
    printf '%s\n' '<key>PayloadType</key><string>Configuration</string>'
    printf '%s\n' '<key>PayloadVersion</key><integer>1</integer>'
    printf '<key>PayloadIdentifier</key><string>%s</string>\n' "$PROFILE_ID"
    printf '<key>PayloadUUID</key><string>%s</string>\n' "$(stable_uuid "$PROFILE_ID")"
    printf '<key>PayloadDisplayName</key><string>%s</string>\n' "$(xml_escape "$PROFILE_NAME")"
    printf '%s\n' '<key>PayloadDescription</key><string>Disables Apple Intelligence features and prevents selected model sets from being re-downloaded. Remove this profile to undo.</string>'
    printf '%s\n' '<key>PayloadOrganization</key><string>Apple AI remover</string>'
    printf '%s\n' '<key>PayloadScope</key><string>System</string>'
    printf '%s\n' '<key>PayloadRemovalDisallowed</key><false/>'
    printf '%s\n' '<key>PayloadContent</key><array>'

    payload_header com.apple.applicationaccess restrictions 'Apple Intelligence restrictions'
    printf '%s\n' '      <key>PayloadContent</key><dict>'
    for feature in "${FEATURES[@]}"; do
      kept "$feature" && continue
      while IFS= read -r key; do
        [[ -n "$key" ]] && printf '        <key>%s</key><false/>\n' "$(xml_escape "$key")"
      done < <(feature_restrictions "$feature")
    done
    printf '%s\n' '      </dict>' '    </dict>'

    for d in com.apple.assistant.support com.apple.Siri group.com.apple.mail group.com.apple.usernoted com.apple.MobileSMS .GlobalPreferences com.apple.spatialphotosrelive; do
      PREF_LINES=''
      while IFS=$'\t' read -r domain key value; do
        [[ "$domain" == "$d" ]] || continue
        PREF_LINES="${PREF_LINES}${key}"$'\t'"${value}"$'\n'
      done <<< "$ALL_PREFS"
      append_pref_payload "$d" "$d" "Forced settings: $d"
    done

    PREF_LINES=''
    while IFS=$'\t' read -r domain key value; do
      [[ "$domain" == 'com.apple.MobileAsset' ]] || continue
      PREF_LINES="${PREF_LINES}${key}"$'\t'"${value}"$'\n'
    done <<< "$ALL_PREFS"
    append_pref_payload com.apple.MobileAsset MobileAsset 'MobileAsset download overrides'

    PREF_LINES="installed"$'\t'true$'\n'"kept"$'\t'"$(keep_csv)"$'\n'
    append_pref_payload "$PROFILE_ID" marker 'Apple AI remover state'

    printf '%s\n' '</array></dict></plist>'
  } > "$tmp"
  /usr/bin/plutil -lint "$tmp" >/dev/null 2>&1 || { rm -f "$tmp"; fail 'generated profile failed plist validation'; }
  mv "$tmp" "$output"
}

keep_csv() {
  local out='' item
  for item in "${KEEP[@]}"; do
    [[ -n "$out" ]] && out="$out,"
    out="$out$item"
  done
  printf '%s' "$out"
}

helper_pref() { "$HELPER" pref "$1" "$2"; }
profile_installed() { local o; o="$(helper_pref "$PROFILE_ID" installed 2>/dev/null)" || return 1; [[ "$o" == *$'forced=1\tvalue=true'* ]]; }
legacy_profile_installed() { local o; o="$(helper_pref "$LEGACY_PROFILE_ID" installed 2>/dev/null)" || return 1; [[ "$o" == *$'forced=1\tvalue=true'* ]]; }
profile_kept_csv() { local o; o="$(helper_pref "$PROFILE_ID" kept 2>/dev/null)" || return 1; printf '%s' "${o#*value=}"; }

validate_uaf_catalog() {
  local set expected actual
  for set in "${MODEL_SETS[@]}"; do
    expected="$(model_set_asset_type "$set")"
    actual="$($HELPER asset-type "$set")" || fail "UAF asset-set lookup failed for $set"
    [[ "$actual" == "$expected" ]] || fail "UAF mapping mismatch for $set: expected $expected, got $actual"
  done
}

model_bytes() {
  local set="$1" out
  out="$($HELPER bytes "$set" 2>/dev/null)" || return 1
  [[ "$out" =~ ^[0-9]+$ ]] || return 1
  printf '%s' "$out"
}

format_bytes() {
  local b="$1"
  if (( b >= 1000000000 )); then awk -v n="$b" 'BEGIN { printf "%.1f GB", n/1e9 }'
  elif (( b > 0 )); then awk -v n="$b" 'BEGIN { printf "%.0f MB", n/1e6 }'
  else echo '0 MB'; fi
}

feature_state() {
  local feature="$1" domain key want output forced value
  local all=1 any=0
  while IFS=$'\t' read -r domain key want; do
    [[ -n "$domain" ]] || continue
    output="$(helper_pref "$domain" "$key" 2>/dev/null)" || { echo unknown; return; }
    forced="$(printf '%s' "$output" | sed -n 's/.*forced=\([^\t]*\).*/\1/p')"
    value="$(printf '%s' "$output" | sed -n 's/.*value=\([^\t]*\)$/\1/p')"
    [[ "$forced" == 1 && "$value" == "$want" ]] && any=1 || all=0
  done < <(feature_preferences "$feature")
  if (( all == 1 && any == 1 )); then echo locked; return; fi

  case "$feature" in
    chatgpt|writing-tools|genmoji|image-playground|safari-summaries|notes-summaries)
      local restricted_ok=1 r
      while IFS= read -r r; do
        [[ -n "$r" ]] || continue
        output="$(helper_pref com.apple.applicationaccess "$r" 2>/dev/null)" || { echo unknown; return; }
        [[ "$output" == *$'forced=1\tvalue=false'* ]] || restricted_ok=0
      done < <(feature_restrictions "$feature")
      (( restricted_ok == 1 )) && echo locked && return
      ;;
  esac

  if profile_installed && ! kept "$feature" && [[ -z "$(feature_preferences "$feature")" ]] && [[ -z "$(feature_restrictions "$feature")" ]]; then
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
  local feature state set n total=0
  for feature in "${FEATURES[@]}"; do
    state="$(feature_state "$feature")"
    printf '%-44s %s\n' "$(feature_title "$feature")" "$state"
  done
  printf '\nModels on disk\n'
  for set in "${MODEL_SETS[@]}"; do
    if n="$(model_bytes "$set")"; then
      total=$((total+n)); printf '  %-44s %s\n' "$(model_set_title "$set")" "$(format_bytes "$n")"
    else
      printf '  %-44s unknown\n' "$(model_set_title "$set")"
    fi
  done
  printf '  %-44s %s\n' Total "$(format_bytes "$total")"
  printf 'Profile: %s\n' "$(profile_installed && echo installed || echo not-installed)"
}

print_features() {
  local f
  for f in "${FEATURES[@]}"; do printf '%-28s %s\n' "$f" "$(feature_title "$f")"; done
}

open_profile_settings() {
  open 'x-apple.systempreferences:com.apple.Profiles-Settings.extension' 2>/dev/null || open 'x-apple.systempreferences:com.apple.preferences.configurationprofiles' 2>/dev/null || true
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
  printf 'Turn off Apple Intelligence and reset the selected models? [y/N] '
  read -r answer
  [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

off_command() {
  parse_args "$@"
  build_helper
  legacy_profile_installed && fail "legacy RemoveMacAI profile is installed; run '$0 revert' first"
  validate_uaf_catalog
  local sets
  sets="$(sets_to_remove)"

  printf 'Features to disable:\n'
  local f
  for f in "${FEATURES[@]}"; do kept "$f" || printf '  - %s\n' "$(feature_title "$f")"; done
  printf 'Model sets to reset:\n%s\n' "$(printf '%s\n' "$sets" | sed 's/^/  - /')"

  if (( DRY_RUN == 1 )); then
    local dry="${TMPDIR:-/tmp}/Apple-AI-remover.$$.mobileconfig"
    build_profile "$dry" "$sets"
    info 'DRY RUN: no profile was installed and no model was reset.'
    info "generated profile: $dry"
    return 0
  fi

  confirm || { info 'Nothing changed.'; return 0; }

  local expected
  expected="$(keep_csv)"
  build_profile "$PROFILE_FILE" "$sets"
  open "$PROFILE_FILE" 2>/dev/null || true
  open_profile_settings
  info "Approve '$PROFILE_NAME' in System Settings."
  wait_for_profile "$expected" || fail 'profile installation was not observed; no model reset was attempted'

  if [[ -n "$sets" ]]; then
    if reset_models "$sets"; then
      info 'All selected model sets reset successfully.'
    else
      fail 'profile is installed, but one or more model resets failed; run status to inspect remaining model state'
    fi
  fi
  info "Done. Run: $0 status"
}

revert_command() {
  build_helper
  local current=0 legacy=0
  profile_installed && current=1
  legacy_profile_installed && legacy=1
  if (( current == 0 && legacy == 0 )); then info 'No Apple AI remover profile is installed.'; return 0; fi
  if (( YES == 0 )); then
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
  local f set x saved_keep all a b
  for f in "${FEATURES[@]}"; do
    feature_title "$f" >/dev/null || fail "missing title for $f"
    while IFS= read -r x; do
      [[ -z "$x" ]] && continue
      model_set_asset_type "$x" >/dev/null || fail "unknown model set $x referenced by $f"
    done < <(feature_model_sets "$f")
  done
  for set in "${MODEL_SETS[@]}"; do model_set_asset_type "$set" >/dev/null || fail "missing model-set mapping $set"; done

  saved_keep=("${KEEP[@]}")
  KEEP=()
  all="$(sets_to_remove)"
  [[ "$(printf '%s\n' "$all" | sort)" == "$(printf '%s\n' "${MODEL_SETS[@]}" | sort)" ]] || fail 'empty keep set must remove every model set'

  KEEP=(writing-tools)
  all="$(sets_to_remove)"
  ! grep -qx 'com.apple.modelcatalog' <<< "$all" || fail 'writing-tools must protect foundation models'
  grep -qx 'com.apple.MobileAsset.UAF.FM.Visual' <<< "$all" || fail 'writing-tools unexpectedly protects visual models'
  KEEP=("${saved_keep[@]}")

  a="$(stable_uuid "$PROFILE_ID")"; b="$(stable_uuid "$PROFILE_ID")"; [[ "$a" == "$b" ]] || fail 'payload UUID generator is not stable'
  printf 'selftest: PASS (%s features, %s model sets)\n' "${#FEATURES[@]}" "${#MODEL_SETS[@]}"
}

usage() {
  cat <<EOF_USAGE
$PRODUCT_NAME $VERSION

Usage:
  $0 status
  $0 features
  $0 off [--keep feature[,feature...]] [--dry-run] [--yes]
  $0 revert [--yes]
  $0 selftest

The mutating commands target macOS $TARGET_MAJOR.x on Apple silicon.
EOF_USAGE
}

main() {
  local command="${1:-status}"
  shift || true
  case "$command" in
    status) require_platform; status_command "$@" ;;
    features) [[ "$#" -eq 0 ]] || fail 'features takes no options'; print_features ;;
    off) require_platform; off_command "$@" ;;
    revert) require_platform; parse_args "$@"; revert_command ;;
    selftest) [[ "$#" -eq 0 ]] || fail 'selftest takes no options'; selftest_command ;;
    --help|-h|help) usage ;;
    --version|-v|version) echo "$VERSION" ;;
    *) usage >&2; exit 1 ;;
  esac
}

main "$@"
forced=1\tvalue=true'* ]]; }
upstream_profile_installed() { local o; o="$(helper_pref "$UPSTREAM_PROFILE_ID" installed 2>/dev/null)" || return 1; [[ "$o" == *
validate_uaf_catalog() {
  local set expected actual
  for set in "${MODEL_SETS[@]}"; do
    expected="$(model_set_asset_type "$set")"
    actual="$($HELPER asset-type "$set")" || fail "UAF asset-set lookup failed for $set"
    [[ "$actual" == "$expected" ]] || fail "UAF mapping mismatch for $set: expected $expected, got $actual"
  done
}

model_bytes() {
  local set="$1" out
  out="$($HELPER bytes "$set" 2>/dev/null)" || return 1
  [[ "$out" =~ ^[0-9]+$ ]] || return 1
  printf '%s' "$out"
}

format_bytes() {
  local b="$1"
  if (( b >= 1000000000 )); then awk -v n="$b" 'BEGIN { printf "%.1f GB", n/1e9 }'
  elif (( b > 0 )); then awk -v n="$b" 'BEGIN { printf "%.0f MB", n/1e6 }'
  else echo '0 MB'; fi
}

feature_state() {
  local feature="$1" domain key want output forced value
  local all=1 any=0
  while IFS=$'\t' read -r domain key want; do
    [[ -n "$domain" ]] || continue
    output="$(helper_pref "$domain" "$key" 2>/dev/null)" || { echo unknown; return; }
    forced="$(printf '%s' "$output" | sed -n 's/.*forced=\([^\t]*\).*/\1/p')"
    value="$(printf '%s' "$output" | sed -n 's/.*value=\([^\t]*\)$/\1/p')"
    [[ "$forced" == 1 && "$value" == "$want" ]] && any=1 || all=0
  done < <(feature_preferences "$feature")
  if (( all == 1 && any == 1 )); then echo locked; return; fi

  case "$feature" in
    chatgpt|writing-tools|genmoji|image-playground|safari-summaries|notes-summaries)
      local restricted_ok=1 r
      while IFS= read -r r; do
        [[ -n "$r" ]] || continue
        output="$(helper_pref com.apple.applicationaccess "$r" 2>/dev/null)" || { echo unknown; return; }
        [[ "$output" == *$'forced=1\tvalue=false'* ]] || restricted_ok=0
      done < <(feature_restrictions "$feature")
      (( restricted_ok == 1 )) && echo locked && return
      ;;
  esac

  if profile_installed && ! kept "$feature" && [[ -z "$(feature_preferences "$feature")" ]] && [[ -z "$(feature_restrictions "$feature")" ]]; then
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
  local feature state set n total=0
  for feature in "${FEATURES[@]}"; do
    state="$(feature_state "$feature")"
    printf '%-44s %s\n' "$(feature_title "$feature")" "$state"
  done
  printf '\nModels on disk\n'
  for set in "${MODEL_SETS[@]}"; do
    if n="$(model_bytes "$set")"; then
      total=$((total+n)); printf '  %-44s %s\n' "$(model_set_title "$set")" "$(format_bytes "$n")"
    else
      printf '  %-44s unknown\n' "$(model_set_title "$set")"
    fi
  done
  printf '  %-44s %s\n' Total "$(format_bytes "$total")"
  printf 'Profile: %s\n' "$(profile_installed && echo installed || echo not-installed)"
}

print_features() {
  local f
  for f in "${FEATURES[@]}"; do printf '%-28s %s\n' "$f" "$(feature_title "$f")"; done
}

open_profile_settings() {
  open 'x-apple.systempreferences:com.apple.Profiles-Settings.extension' 2>/dev/null || open 'x-apple.systempreferences:com.apple.preferences.configurationprofiles' 2>/dev/null || true
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
  printf 'Turn off Apple Intelligence and reset the selected models? [y/N] '
  read -r answer
  [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

off_command() {
  parse_args "$@"
  build_helper
  legacy_profile_installed && fail "legacy RemoveMacAI profile is installed; run '$0 revert' first"
  validate_uaf_catalog
  local sets
  sets="$(sets_to_remove)"

  printf 'Features to disable:\n'
  local f
  for f in "${FEATURES[@]}"; do kept "$f" || printf '  - %s\n' "$(feature_title "$f")"; done
  printf 'Model sets to reset:\n%s\n' "$(printf '%s\n' "$sets" | sed 's/^/  - /')"

  if (( DRY_RUN == 1 )); then
    local dry="${TMPDIR:-/tmp}/Apple-AI-remover.$$.mobileconfig"
    build_profile "$dry" "$sets"
    info 'DRY RUN: no profile was installed and no model was reset.'
    info "generated profile: $dry"
    return 0
  fi

  confirm || { info 'Nothing changed.'; return 0; }

  local expected
  expected="$(keep_csv)"
  build_profile "$PROFILE_FILE" "$sets"
  open "$PROFILE_FILE" 2>/dev/null || true
  open_profile_settings
  info "Approve '$PROFILE_NAME' in System Settings."
  wait_for_profile "$expected" || fail 'profile installation was not observed; no model reset was attempted'

  if [[ -n "$sets" ]]; then
    if reset_models "$sets"; then
      info 'All selected model sets reset successfully.'
    else
      fail 'profile is installed, but one or more model resets failed; run status to inspect remaining model state'
    fi
  fi
  info "Done. Run: $0 status"
}

revert_command() {
  build_helper
  local current=0 legacy=0
  profile_installed && current=1
  legacy_profile_installed && legacy=1
  if (( current == 0 && legacy == 0 )); then info 'No Apple AI remover profile is installed.'; return 0; fi
  if (( YES == 0 )); then
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
  local f set x saved_keep all a b
  for f in "${FEATURES[@]}"; do
    feature_title "$f" >/dev/null || fail "missing title for $f"
    while IFS= read -r x; do
      [[ -z "$x" ]] && continue
      model_set_asset_type "$x" >/dev/null || fail "unknown model set $x referenced by $f"
    done < <(feature_model_sets "$f")
  done
  for set in "${MODEL_SETS[@]}"; do model_set_asset_type "$set" >/dev/null || fail "missing model-set mapping $set"; done

  saved_keep=("${KEEP[@]}")
  KEEP=()
  all="$(sets_to_remove)"
  [[ "$(printf '%s\n' "$all" | sort)" == "$(printf '%s\n' "${MODEL_SETS[@]}" | sort)" ]] || fail 'empty keep set must remove every model set'

  KEEP=(writing-tools)
  all="$(sets_to_remove)"
  ! grep -qx 'com.apple.modelcatalog' <<< "$all" || fail 'writing-tools must protect foundation models'
  grep -qx 'com.apple.MobileAsset.UAF.FM.Visual' <<< "$all" || fail 'writing-tools unexpectedly protects visual models'
  KEEP=("${saved_keep[@]}")

  a="$(stable_uuid "$PROFILE_ID")"; b="$(stable_uuid "$PROFILE_ID")"; [[ "$a" == "$b" ]] || fail 'payload UUID generator is not stable'
  printf 'selftest: PASS (%s features, %s model sets)\n' "${#FEATURES[@]}" "${#MODEL_SETS[@]}"
}

usage() {
  cat <<EOF_USAGE
$PRODUCT_NAME $VERSION

Usage:
  $0 status
  $0 features
  $0 off [--keep feature[,feature...]] [--dry-run] [--yes]
  $0 revert [--yes]
  $0 selftest

The mutating commands target macOS $TARGET_MAJOR.x on Apple silicon.
EOF_USAGE
}

main() {
  local command="${1:-status}"
  shift || true
  case "$command" in
    status) require_platform; status_command "$@" ;;
    features) [[ "$#" -eq 0 ]] || fail 'features takes no options'; print_features ;;
    off) require_platform; off_command "$@" ;;
    revert) require_platform; parse_args "$@"; revert_command ;;
    selftest) [[ "$#" -eq 0 ]] || fail 'selftest takes no options'; selftest_command ;;
    --help|-h|help) usage ;;
    --version|-v|version) echo "$VERSION" ;;
    *) usage >&2; exit 1 ;;
  esac
}

main "$@"
\t'"${value}"
    [[ -n "$set" ]] || continue
    key="DownloadServerBaseURLOverride-$(model_set_asset_type "$set")"
    PREF_LINES="${PREF_LINES}com.apple.MobileAsset"$'\t'"${key}"$'\t'"${BLOCKED_URL}"$'\n'
  done <<< "$sets"

  mkdir -p "$(dirname "$output")"
  {
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
    printf '%s\n' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    printf '%s\n' '<plist version="1.0"><dict>'
    printf '%s\n' '<key>PayloadType</key><string>Configuration</string>'
    printf '%s\n' '<key>PayloadVersion</key><integer>1</integer>'
    printf '<key>PayloadIdentifier</key><string>%s</string>\n' "$PROFILE_ID"
    printf '<key>PayloadUUID</key><string>%s</string>\n' "$(stable_uuid "$PROFILE_ID")"
    printf '<key>PayloadDisplayName</key><string>%s</string>\n' "$(xml_escape "$PROFILE_NAME")"
    printf '%s\n' '<key>PayloadDescription</key><string>Disables Apple Intelligence features and prevents selected model sets from being re-downloaded. Remove this profile to undo.</string>'
    printf '%s\n' '<key>PayloadOrganization</key><string>Apple AI remover</string>'
    printf '%s\n' '<key>PayloadScope</key><string>System</string>'
    printf '%s\n' '<key>PayloadRemovalDisallowed</key><false/>'
    printf '%s\n' '<key>PayloadContent</key><array>'

    payload_header com.apple.applicationaccess restrictions 'Apple Intelligence restrictions'
    printf '%s\n' '      <key>PayloadContent</key><dict>'
    for feature in "${FEATURES[@]}"; do
      kept "$feature" && continue
      while IFS= read -r key; do
        [[ -n "$key" ]] && printf '        <key>%s</key><false/>\n' "$(xml_escape "$key")"
      done < <(feature_restrictions "$feature")
    done
    printf '%s\n' '      </dict>' '    </dict>'

    for d in com.apple.assistant.support com.apple.Siri group.com.apple.mail group.com.apple.usernoted com.apple.MobileSMS .GlobalPreferences com.apple.spatialphotosrelive; do
      PREF_LINES=''
      while IFS=$'\t' read -r domain key value; do
        [[ "$domain" == "$d" ]] || continue
        PREF_LINES="${PREF_LINES}${key}"$'\t'"${value}"$'\n'
      done <<< "$ALL_PREFS"
      append_pref_payload "$d" "$d" "Forced settings: $d"
    done

    PREF_LINES=''
    while IFS=$'\t' read -r domain key value; do
      [[ "$domain" == 'com.apple.MobileAsset' ]] || continue
      PREF_LINES="${PREF_LINES}${key}"$'\t'"${value}"$'\n'
    done <<< "$ALL_PREFS"
    append_pref_payload com.apple.MobileAsset MobileAsset 'MobileAsset download overrides'

    PREF_LINES="installed"$'\t'true$'\n'"kept"$'\t'"$(keep_csv)"$'\n'
    append_pref_payload "$PROFILE_ID" marker 'Apple AI remover state'

    printf '%s\n' '</array></dict></plist>'
  } > "$tmp"
  /usr/bin/plutil -lint "$tmp" >/dev/null 2>&1 || { rm -f "$tmp"; fail 'generated profile failed plist validation'; }
  mv "$tmp" "$output"
}

keep_csv() {
  local out='' item
  for item in "${KEEP[@]}"; do
    [[ -n "$out" ]] && out="$out,"
    out="$out$item"
  done
  printf '%s' "$out"
}

helper_pref() { "$HELPER" pref "$1" "$2"; }
profile_installed() { local o; o="$(helper_pref "$PROFILE_ID" installed 2>/dev/null)" || return 1; [[ "$o" == *$'forced=1\tvalue=true'* ]]; }
legacy_profile_installed() { local o; o="$(helper_pref "$LEGACY_PROFILE_ID" installed 2>/dev/null)" || return 1; [[ "$o" == *$'forced=1\tvalue=true'* ]]; }
profile_kept_csv() { local o; o="$(helper_pref "$PROFILE_ID" kept 2>/dev/null)" || return 1; printf '%s' "${o#*value=}"; }

validate_uaf_catalog() {
  local set expected actual
  for set in "${MODEL_SETS[@]}"; do
    expected="$(model_set_asset_type "$set")"
    actual="$($HELPER asset-type "$set")" || fail "UAF asset-set lookup failed for $set"
    [[ "$actual" == "$expected" ]] || fail "UAF mapping mismatch for $set: expected $expected, got $actual"
  done
}

model_bytes() {
  local set="$1" out
  out="$($HELPER bytes "$set" 2>/dev/null)" || return 1
  [[ "$out" =~ ^[0-9]+$ ]] || return 1
  printf '%s' "$out"
}

format_bytes() {
  local b="$1"
  if (( b >= 1000000000 )); then awk -v n="$b" 'BEGIN { printf "%.1f GB", n/1e9 }'
  elif (( b > 0 )); then awk -v n="$b" 'BEGIN { printf "%.0f MB", n/1e6 }'
  else echo '0 MB'; fi
}

feature_state() {
  local feature="$1" domain key want output forced value
  local all=1 any=0
  while IFS=$'\t' read -r domain key want; do
    [[ -n "$domain" ]] || continue
    output="$(helper_pref "$domain" "$key" 2>/dev/null)" || { echo unknown; return; }
    forced="$(printf '%s' "$output" | sed -n 's/.*forced=\([^\t]*\).*/\1/p')"
    value="$(printf '%s' "$output" | sed -n 's/.*value=\([^\t]*\)$/\1/p')"
    [[ "$forced" == 1 && "$value" == "$want" ]] && any=1 || all=0
  done < <(feature_preferences "$feature")
  if (( all == 1 && any == 1 )); then echo locked; return; fi

  case "$feature" in
    chatgpt|writing-tools|genmoji|image-playground|safari-summaries|notes-summaries)
      local restricted_ok=1 r
      while IFS= read -r r; do
        [[ -n "$r" ]] || continue
        output="$(helper_pref com.apple.applicationaccess "$r" 2>/dev/null)" || { echo unknown; return; }
        [[ "$output" == *$'forced=1\tvalue=false'* ]] || restricted_ok=0
      done < <(feature_restrictions "$feature")
      (( restricted_ok == 1 )) && echo locked && return
      ;;
  esac

  if profile_installed && ! kept "$feature" && [[ -z "$(feature_preferences "$feature")" ]] && [[ -z "$(feature_restrictions "$feature")" ]]; then
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
  local feature state set n total=0
  for feature in "${FEATURES[@]}"; do
    state="$(feature_state "$feature")"
    printf '%-44s %s\n' "$(feature_title "$feature")" "$state"
  done
  printf '\nModels on disk\n'
  for set in "${MODEL_SETS[@]}"; do
    if n="$(model_bytes "$set")"; then
      total=$((total+n)); printf '  %-44s %s\n' "$(model_set_title "$set")" "$(format_bytes "$n")"
    else
      printf '  %-44s unknown\n' "$(model_set_title "$set")"
    fi
  done
  printf '  %-44s %s\n' Total "$(format_bytes "$total")"
  printf 'Profile: %s\n' "$(profile_installed && echo installed || echo not-installed)"
}

print_features() {
  local f
  for f in "${FEATURES[@]}"; do printf '%-28s %s\n' "$f" "$(feature_title "$f")"; done
}

open_profile_settings() {
  open 'x-apple.systempreferences:com.apple.Profiles-Settings.extension' 2>/dev/null || open 'x-apple.systempreferences:com.apple.preferences.configurationprofiles' 2>/dev/null || true
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
  printf 'Turn off Apple Intelligence and reset the selected models? [y/N] '
  read -r answer
  [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

off_command() {
  parse_args "$@"
  build_helper
  legacy_profile_installed && fail "legacy RemoveMacAI profile is installed; run '$0 revert' first"
  validate_uaf_catalog
  local sets
  sets="$(sets_to_remove)"

  printf 'Features to disable:\n'
  local f
  for f in "${FEATURES[@]}"; do kept "$f" || printf '  - %s\n' "$(feature_title "$f")"; done
  printf 'Model sets to reset:\n%s\n' "$(printf '%s\n' "$sets" | sed 's/^/  - /')"

  if (( DRY_RUN == 1 )); then
    local dry="${TMPDIR:-/tmp}/Apple-AI-remover.$$.mobileconfig"
    build_profile "$dry" "$sets"
    info 'DRY RUN: no profile was installed and no model was reset.'
    info "generated profile: $dry"
    return 0
  fi

  confirm || { info 'Nothing changed.'; return 0; }

  local expected
  expected="$(keep_csv)"
  build_profile "$PROFILE_FILE" "$sets"
  open "$PROFILE_FILE" 2>/dev/null || true
  open_profile_settings
  info "Approve '$PROFILE_NAME' in System Settings."
  wait_for_profile "$expected" || fail 'profile installation was not observed; no model reset was attempted'

  if [[ -n "$sets" ]]; then
    if reset_models "$sets"; then
      info 'All selected model sets reset successfully.'
    else
      fail 'profile is installed, but one or more model resets failed; run status to inspect remaining model state'
    fi
  fi
  info "Done. Run: $0 status"
}

revert_command() {
  build_helper
  local current=0 legacy=0
  profile_installed && current=1
  legacy_profile_installed && legacy=1
  if (( current == 0 && legacy == 0 )); then info 'No Apple AI remover profile is installed.'; return 0; fi
  if (( YES == 0 )); then
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
  local f set x saved_keep all a b
  for f in "${FEATURES[@]}"; do
    feature_title "$f" >/dev/null || fail "missing title for $f"
    while IFS= read -r x; do
      [[ -z "$x" ]] && continue
      model_set_asset_type "$x" >/dev/null || fail "unknown model set $x referenced by $f"
    done < <(feature_model_sets "$f")
  done
  for set in "${MODEL_SETS[@]}"; do model_set_asset_type "$set" >/dev/null || fail "missing model-set mapping $set"; done

  saved_keep=("${KEEP[@]}")
  KEEP=()
  all="$(sets_to_remove)"
  [[ "$(printf '%s\n' "$all" | sort)" == "$(printf '%s\n' "${MODEL_SETS[@]}" | sort)" ]] || fail 'empty keep set must remove every model set'

  KEEP=(writing-tools)
  all="$(sets_to_remove)"
  ! grep -qx 'com.apple.modelcatalog' <<< "$all" || fail 'writing-tools must protect foundation models'
  grep -qx 'com.apple.MobileAsset.UAF.FM.Visual' <<< "$all" || fail 'writing-tools unexpectedly protects visual models'
  KEEP=("${saved_keep[@]}")

  a="$(stable_uuid "$PROFILE_ID")"; b="$(stable_uuid "$PROFILE_ID")"; [[ "$a" == "$b" ]] || fail 'payload UUID generator is not stable'
  printf 'selftest: PASS (%s features, %s model sets)\n' "${#FEATURES[@]}" "${#MODEL_SETS[@]}"
}

usage() {
  cat <<EOF_USAGE
$PRODUCT_NAME $VERSION

Usage:
  $0 status
  $0 features
  $0 off [--keep feature[,feature...]] [--dry-run] [--yes]
  $0 revert [--yes]
  $0 selftest

The mutating commands target macOS $TARGET_MAJOR.x on Apple silicon.
EOF_USAGE
}

main() {
  local command="${1:-status}"
  shift || true
  case "$command" in
    status) require_platform; status_command "$@" ;;
    features) [[ "$#" -eq 0 ]] || fail 'features takes no options'; print_features ;;
    off) require_platform; off_command "$@" ;;
    revert) require_platform; parse_args "$@"; revert_command ;;
    selftest) [[ "$#" -eq 0 ]] || fail 'selftest takes no options'; selftest_command ;;
    --help|-h|help) usage ;;
    --version|-v|version) echo "$VERSION" ;;
    *) usage >&2; exit 1 ;;
  esac
}

main "$@"
\n'
    done < <(feature_preferences "$feature")
  done
  while IFS= read -r set; do
    [[ -n "$set" ]] || continue
    key="DownloadServerBaseURLOverride-$(model_set_asset_type "$set")"
    PREF_LINES="${PREF_LINES}com.apple.MobileAsset"$'\t'"${key}"$'\t'"${BLOCKED_URL}"$'\n'
  done <<< "$sets"

  mkdir -p "$(dirname "$output")"
  {
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
    printf '%s\n' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    printf '%s\n' '<plist version="1.0"><dict>'
    printf '%s\n' '<key>PayloadType</key><string>Configuration</string>'
    printf '%s\n' '<key>PayloadVersion</key><integer>1</integer>'
    printf '<key>PayloadIdentifier</key><string>%s</string>\n' "$PROFILE_ID"
    printf '<key>PayloadUUID</key><string>%s</string>\n' "$(stable_uuid "$PROFILE_ID")"
    printf '<key>PayloadDisplayName</key><string>%s</string>\n' "$(xml_escape "$PROFILE_NAME")"
    printf '%s\n' '<key>PayloadDescription</key><string>Disables Apple Intelligence features and prevents selected model sets from being re-downloaded. Remove this profile to undo.</string>'
    printf '%s\n' '<key>PayloadOrganization</key><string>Apple AI remover</string>'
    printf '%s\n' '<key>PayloadScope</key><string>System</string>'
    printf '%s\n' '<key>PayloadRemovalDisallowed</key><false/>'
    printf '%s\n' '<key>PayloadContent</key><array>'

    payload_header com.apple.applicationaccess restrictions 'Apple Intelligence restrictions'
    printf '%s\n' '      <key>PayloadContent</key><dict>'
    for feature in "${FEATURES[@]}"; do
      kept "$feature" && continue
      while IFS= read -r key; do
        [[ -n "$key" ]] && printf '        <key>%s</key><false/>\n' "$(xml_escape "$key")"
      done < <(feature_restrictions "$feature")
    done
    printf '%s\n' '      </dict>' '    </dict>'

    for d in com.apple.assistant.support com.apple.Siri group.com.apple.mail group.com.apple.usernoted com.apple.MobileSMS .GlobalPreferences com.apple.spatialphotosrelive; do
      PREF_LINES=''
      while IFS=$'\t' read -r domain key value; do
        [[ "$domain" == "$d" ]] || continue
        PREF_LINES="${PREF_LINES}${key}"$'\t'"${value}"$'\n'
      done <<< "$ALL_PREFS"
      append_pref_payload "$d" "$d" "Forced settings: $d"
    done

    PREF_LINES=''
    while IFS=$'\t' read -r domain key value; do
      [[ "$domain" == 'com.apple.MobileAsset' ]] || continue
      PREF_LINES="${PREF_LINES}${key}"$'\t'"${value}"$'\n'
    done <<< "$ALL_PREFS"
    append_pref_payload com.apple.MobileAsset MobileAsset 'MobileAsset download overrides'

    PREF_LINES="installed"$'\t'true$'\n'"kept"$'\t'"$(keep_csv)"$'\n'
    append_pref_payload "$PROFILE_ID" marker 'Apple AI remover state'

    printf '%s\n' '</array></dict></plist>'
  } > "$tmp"
  /usr/bin/plutil -lint "$tmp" >/dev/null 2>&1 || { rm -f "$tmp"; fail 'generated profile failed plist validation'; }
  mv "$tmp" "$output"
}

keep_csv() {
  local out='' item
  for item in "${KEEP[@]}"; do
    [[ -n "$out" ]] && out="$out,"
    out="$out$item"
  done
  printf '%s' "$out"
}

helper_pref() { "$HELPER" pref "$1" "$2"; }
profile_installed() { local o; o="$(helper_pref "$PROFILE_ID" installed 2>/dev/null)" || return 1; [[ "$o" == *$'forced=1\tvalue=true'* ]]; }
legacy_profile_installed() { local o; o="$(helper_pref "$LEGACY_PROFILE_ID" installed 2>/dev/null)" || return 1; [[ "$o" == *$'forced=1\tvalue=true'* ]]; }
profile_kept_csv() { local o; o="$(helper_pref "$PROFILE_ID" kept 2>/dev/null)" || return 1; printf '%s' "${o#*value=}"; }

validate_uaf_catalog() {
  local set expected actual
  for set in "${MODEL_SETS[@]}"; do
    expected="$(model_set_asset_type "$set")"
    actual="$($HELPER asset-type "$set")" || fail "UAF asset-set lookup failed for $set"
    [[ "$actual" == "$expected" ]] || fail "UAF mapping mismatch for $set: expected $expected, got $actual"
  done
}

model_bytes() {
  local set="$1" out
  out="$($HELPER bytes "$set" 2>/dev/null)" || return 1
  [[ "$out" =~ ^[0-9]+$ ]] || return 1
  printf '%s' "$out"
}

format_bytes() {
  local b="$1"
  if (( b >= 1000000000 )); then awk -v n="$b" 'BEGIN { printf "%.1f GB", n/1e9 }'
  elif (( b > 0 )); then awk -v n="$b" 'BEGIN { printf "%.0f MB", n/1e6 }'
  else echo '0 MB'; fi
}

feature_state() {
  local feature="$1" domain key want output forced value
  local all=1 any=0
  while IFS=$'\t' read -r domain key want; do
    [[ -n "$domain" ]] || continue
    output="$(helper_pref "$domain" "$key" 2>/dev/null)" || { echo unknown; return; }
    forced="$(printf '%s' "$output" | sed -n 's/.*forced=\([^\t]*\).*/\1/p')"
    value="$(printf '%s' "$output" | sed -n 's/.*value=\([^\t]*\)$/\1/p')"
    [[ "$forced" == 1 && "$value" == "$want" ]] && any=1 || all=0
  done < <(feature_preferences "$feature")
  if (( all == 1 && any == 1 )); then echo locked; return; fi

  case "$feature" in
    chatgpt|writing-tools|genmoji|image-playground|safari-summaries|notes-summaries)
      local restricted_ok=1 r
      while IFS= read -r r; do
        [[ -n "$r" ]] || continue
        output="$(helper_pref com.apple.applicationaccess "$r" 2>/dev/null)" || { echo unknown; return; }
        [[ "$output" == *$'forced=1\tvalue=false'* ]] || restricted_ok=0
      done < <(feature_restrictions "$feature")
      (( restricted_ok == 1 )) && echo locked && return
      ;;
  esac

  if profile_installed && ! kept "$feature" && [[ -z "$(feature_preferences "$feature")" ]] && [[ -z "$(feature_restrictions "$feature")" ]]; then
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
  local feature state set n total=0
  for feature in "${FEATURES[@]}"; do
    state="$(feature_state "$feature")"
    printf '%-44s %s\n' "$(feature_title "$feature")" "$state"
  done
  printf '\nModels on disk\n'
  for set in "${MODEL_SETS[@]}"; do
    if n="$(model_bytes "$set")"; then
      total=$((total+n)); printf '  %-44s %s\n' "$(model_set_title "$set")" "$(format_bytes "$n")"
    else
      printf '  %-44s unknown\n' "$(model_set_title "$set")"
    fi
  done
  printf '  %-44s %s\n' Total "$(format_bytes "$total")"
  printf 'Profile: %s\n' "$(profile_installed && echo installed || echo not-installed)"
}

print_features() {
  local f
  for f in "${FEATURES[@]}"; do printf '%-28s %s\n' "$f" "$(feature_title "$f")"; done
}

open_profile_settings() {
  open 'x-apple.systempreferences:com.apple.Profiles-Settings.extension' 2>/dev/null || open 'x-apple.systempreferences:com.apple.preferences.configurationprofiles' 2>/dev/null || true
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
  printf 'Turn off Apple Intelligence and reset the selected models? [y/N] '
  read -r answer
  [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

off_command() {
  parse_args "$@"
  build_helper
  legacy_profile_installed && fail "legacy RemoveMacAI profile is installed; run '$0 revert' first"
  validate_uaf_catalog
  local sets
  sets="$(sets_to_remove)"

  printf 'Features to disable:\n'
  local f
  for f in "${FEATURES[@]}"; do kept "$f" || printf '  - %s\n' "$(feature_title "$f")"; done
  printf 'Model sets to reset:\n%s\n' "$(printf '%s\n' "$sets" | sed 's/^/  - /')"

  if (( DRY_RUN == 1 )); then
    local dry="${TMPDIR:-/tmp}/Apple-AI-remover.$$.mobileconfig"
    build_profile "$dry" "$sets"
    info 'DRY RUN: no profile was installed and no model was reset.'
    info "generated profile: $dry"
    return 0
  fi

  confirm || { info 'Nothing changed.'; return 0; }

  local expected
  expected="$(keep_csv)"
  build_profile "$PROFILE_FILE" "$sets"
  open "$PROFILE_FILE" 2>/dev/null || true
  open_profile_settings
  info "Approve '$PROFILE_NAME' in System Settings."
  wait_for_profile "$expected" || fail 'profile installation was not observed; no model reset was attempted'

  if [[ -n "$sets" ]]; then
    if reset_models "$sets"; then
      info 'All selected model sets reset successfully.'
    else
      fail 'profile is installed, but one or more model resets failed; run status to inspect remaining model state'
    fi
  fi
  info "Done. Run: $0 status"
}

revert_command() {
  build_helper
  local current=0 legacy=0
  profile_installed && current=1
  legacy_profile_installed && legacy=1
  if (( current == 0 && legacy == 0 )); then info 'No Apple AI remover profile is installed.'; return 0; fi
  if (( YES == 0 )); then
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
  local f set x saved_keep all a b
  for f in "${FEATURES[@]}"; do
    feature_title "$f" >/dev/null || fail "missing title for $f"
    while IFS= read -r x; do
      [[ -z "$x" ]] && continue
      model_set_asset_type "$x" >/dev/null || fail "unknown model set $x referenced by $f"
    done < <(feature_model_sets "$f")
  done
  for set in "${MODEL_SETS[@]}"; do model_set_asset_type "$set" >/dev/null || fail "missing model-set mapping $set"; done

  saved_keep=("${KEEP[@]}")
  KEEP=()
  all="$(sets_to_remove)"
  [[ "$(printf '%s\n' "$all" | sort)" == "$(printf '%s\n' "${MODEL_SETS[@]}" | sort)" ]] || fail 'empty keep set must remove every model set'

  KEEP=(writing-tools)
  all="$(sets_to_remove)"
  ! grep -qx 'com.apple.modelcatalog' <<< "$all" || fail 'writing-tools must protect foundation models'
  grep -qx 'com.apple.MobileAsset.UAF.FM.Visual' <<< "$all" || fail 'writing-tools unexpectedly protects visual models'
  KEEP=("${saved_keep[@]}")

  a="$(stable_uuid "$PROFILE_ID")"; b="$(stable_uuid "$PROFILE_ID")"; [[ "$a" == "$b" ]] || fail 'payload UUID generator is not stable'
  printf 'selftest: PASS (%s features, %s model sets)\n' "${#FEATURES[@]}" "${#MODEL_SETS[@]}"
}

usage() {
  cat <<EOF_USAGE
$PRODUCT_NAME $VERSION

Usage:
  $0 status
  $0 features
  $0 off [--keep feature[,feature...]] [--dry-run] [--yes]
  $0 revert [--yes]
  $0 selftest

The mutating commands target macOS $TARGET_MAJOR.x on Apple silicon.
EOF_USAGE
}

main() {
  local command="${1:-status}"
  shift || true
  case "$command" in
    status) require_platform; status_command "$@" ;;
    features) [[ "$#" -eq 0 ]] || fail 'features takes no options'; print_features ;;
    off) require_platform; off_command "$@" ;;
    revert) require_platform; parse_args "$@"; revert_command ;;
    selftest) [[ "$#" -eq 0 ]] || fail 'selftest takes no options'; selftest_command ;;
    --help|-h|help) usage ;;
    --version|-v|version) echo "$VERSION" ;;
    *) usage >&2; exit 1 ;;
  esac
}

main "$@"
forced=1\tvalue=true'* ]]; }
upstream_profile_installed() { local o; o="$(helper_pref "$UPSTREAM_PROFILE_ID" installed 2>/dev/null)" || return 1; [[ "$o" == * { local o; o="$(helper_pref "$PROFILE_ID" kept 2>/dev/null)" || return 1; printf '%s' "${o#*value=}"; }

validate_uaf_catalog() {
  local set expected actual
  for set in "${MODEL_SETS[@]}"; do
    expected="$(model_set_asset_type "$set")"
    actual="$($HELPER asset-type "$set")" || fail "UAF asset-set lookup failed for $set"
    [[ "$actual" == "$expected" ]] || fail "UAF mapping mismatch for $set: expected $expected, got $actual"
  done
}

model_bytes() {
  local set="$1" out
  out="$($HELPER bytes "$set" 2>/dev/null)" || return 1
  [[ "$out" =~ ^[0-9]+$ ]] || return 1
  printf '%s' "$out"
}

format_bytes() {
  local b="$1"
  if (( b >= 1000000000 )); then awk -v n="$b" 'BEGIN { printf "%.1f GB", n/1e9 }'
  elif (( b > 0 )); then awk -v n="$b" 'BEGIN { printf "%.0f MB", n/1e6 }'
  else echo '0 MB'; fi
}

feature_state() {
  local feature="$1" domain key want output forced value
  local all=1 any=0
  while IFS=$'\t' read -r domain key want; do
    [[ -n "$domain" ]] || continue
    output="$(helper_pref "$domain" "$key" 2>/dev/null)" || { echo unknown; return; }
    forced="$(printf '%s' "$output" | sed -n 's/.*forced=\([^\t]*\).*/\1/p')"
    value="$(printf '%s' "$output" | sed -n 's/.*value=\([^\t]*\)$/\1/p')"
    [[ "$forced" == 1 && "$value" == "$want" ]] && any=1 || all=0
  done < <(feature_preferences "$feature")
  if (( all == 1 && any == 1 )); then echo locked; return; fi

  case "$feature" in
    chatgpt|writing-tools|genmoji|image-playground|safari-summaries|notes-summaries)
      local restricted_ok=1 r
      while IFS= read -r r; do
        [[ -n "$r" ]] || continue
        output="$(helper_pref com.apple.applicationaccess "$r" 2>/dev/null)" || { echo unknown; return; }
        [[ "$output" == *$'forced=1\tvalue=false'* ]] || restricted_ok=0
      done < <(feature_restrictions "$feature")
      (( restricted_ok == 1 )) && echo locked && return
      ;;
  esac

  if profile_installed && ! kept "$feature" && [[ -z "$(feature_preferences "$feature")" ]] && [[ -z "$(feature_restrictions "$feature")" ]]; then
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
  local feature state set n total=0
  for feature in "${FEATURES[@]}"; do
    state="$(feature_state "$feature")"
    printf '%-44s %s\n' "$(feature_title "$feature")" "$state"
  done
  printf '\nModels on disk\n'
  for set in "${MODEL_SETS[@]}"; do
    if n="$(model_bytes "$set")"; then
      total=$((total+n)); printf '  %-44s %s\n' "$(model_set_title "$set")" "$(format_bytes "$n")"
    else
      printf '  %-44s unknown\n' "$(model_set_title "$set")"
    fi
  done
  printf '  %-44s %s\n' Total "$(format_bytes "$total")"
  printf 'Profile: %s\n' "$(profile_installed && echo installed || echo not-installed)"
}

print_features() {
  local f
  for f in "${FEATURES[@]}"; do printf '%-28s %s\n' "$f" "$(feature_title "$f")"; done
}

open_profile_settings() {
  open 'x-apple.systempreferences:com.apple.Profiles-Settings.extension' 2>/dev/null || open 'x-apple.systempreferences:com.apple.preferences.configurationprofiles' 2>/dev/null || true
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
  printf 'Turn off Apple Intelligence and reset the selected models? [y/N] '
  read -r answer
  [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

off_command() {
  parse_args "$@"
  build_helper
  legacy_profile_installed && fail "legacy RemoveMacAI profile is installed; run '$0 revert' first"
  validate_uaf_catalog
  local sets
  sets="$(sets_to_remove)"

  printf 'Features to disable:\n'
  local f
  for f in "${FEATURES[@]}"; do kept "$f" || printf '  - %s\n' "$(feature_title "$f")"; done
  printf 'Model sets to reset:\n%s\n' "$(printf '%s\n' "$sets" | sed 's/^/  - /')"

  if (( DRY_RUN == 1 )); then
    local dry="${TMPDIR:-/tmp}/Apple-AI-remover.$$.mobileconfig"
    build_profile "$dry" "$sets"
    info 'DRY RUN: no profile was installed and no model was reset.'
    info "generated profile: $dry"
    return 0
  fi

  confirm || { info 'Nothing changed.'; return 0; }

  local expected
  expected="$(keep_csv)"
  build_profile "$PROFILE_FILE" "$sets"
  open "$PROFILE_FILE" 2>/dev/null || true
  open_profile_settings
  info "Approve '$PROFILE_NAME' in System Settings."
  wait_for_profile "$expected" || fail 'profile installation was not observed; no model reset was attempted'

  if [[ -n "$sets" ]]; then
    if reset_models "$sets"; then
      info 'All selected model sets reset successfully.'
    else
      fail 'profile is installed, but one or more model resets failed; run status to inspect remaining model state'
    fi
  fi
  info "Done. Run: $0 status"
}

revert_command() {
  build_helper
  local current=0 legacy=0
  profile_installed && current=1
  legacy_profile_installed && legacy=1
  if (( current == 0 && legacy == 0 )); then info 'No Apple AI remover profile is installed.'; return 0; fi
  if (( YES == 0 )); then
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
  local f set x saved_keep all a b
  for f in "${FEATURES[@]}"; do
    feature_title "$f" >/dev/null || fail "missing title for $f"
    while IFS= read -r x; do
      [[ -z "$x" ]] && continue
      model_set_asset_type "$x" >/dev/null || fail "unknown model set $x referenced by $f"
    done < <(feature_model_sets "$f")
  done
  for set in "${MODEL_SETS[@]}"; do model_set_asset_type "$set" >/dev/null || fail "missing model-set mapping $set"; done

  saved_keep=("${KEEP[@]}")
  KEEP=()
  all="$(sets_to_remove)"
  [[ "$(printf '%s\n' "$all" | sort)" == "$(printf '%s\n' "${MODEL_SETS[@]}" | sort)" ]] || fail 'empty keep set must remove every model set'

  KEEP=(writing-tools)
  all="$(sets_to_remove)"
  ! grep -qx 'com.apple.modelcatalog' <<< "$all" || fail 'writing-tools must protect foundation models'
  grep -qx 'com.apple.MobileAsset.UAF.FM.Visual' <<< "$all" || fail 'writing-tools unexpectedly protects visual models'
  KEEP=("${saved_keep[@]}")

  a="$(stable_uuid "$PROFILE_ID")"; b="$(stable_uuid "$PROFILE_ID")"; [[ "$a" == "$b" ]] || fail 'payload UUID generator is not stable'
  printf 'selftest: PASS (%s features, %s model sets)\n' "${#FEATURES[@]}" "${#MODEL_SETS[@]}"
}

usage() {
  cat <<EOF_USAGE
$PRODUCT_NAME $VERSION

Usage:
  $0 status
  $0 features
  $0 off [--keep feature[,feature...]] [--dry-run] [--yes]
  $0 revert [--yes]
  $0 selftest

The mutating commands target macOS $TARGET_MAJOR.x on Apple silicon.
EOF_USAGE
}

main() {
  local command="${1:-status}"
  shift || true
  case "$command" in
    status) require_platform; status_command "$@" ;;
    features) [[ "$#" -eq 0 ]] || fail 'features takes no options'; print_features ;;
    off) require_platform; off_command "$@" ;;
    revert) require_platform; parse_args "$@"; revert_command ;;
    selftest) [[ "$#" -eq 0 ]] || fail 'selftest takes no options'; selftest_command ;;
    --help|-h|help) usage ;;
    --version|-v|version) echo "$VERSION" ;;
    *) usage >&2; exit 1 ;;
  esac
}

main "$@"
\t'"${key}"
    [[ -n "$set" ]] || continue
    key="DownloadServerBaseURLOverride-$(model_set_asset_type "$set")"
    PREF_LINES="${PREF_LINES}com.apple.MobileAsset"$'\t'"${key}"$'\t'"${BLOCKED_URL}"$'\n'
  done <<< "$sets"

  mkdir -p "$(dirname "$output")"
  {
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
    printf '%s\n' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    printf '%s\n' '<plist version="1.0"><dict>'
    printf '%s\n' '<key>PayloadType</key><string>Configuration</string>'
    printf '%s\n' '<key>PayloadVersion</key><integer>1</integer>'
    printf '<key>PayloadIdentifier</key><string>%s</string>\n' "$PROFILE_ID"
    printf '<key>PayloadUUID</key><string>%s</string>\n' "$(stable_uuid "$PROFILE_ID")"
    printf '<key>PayloadDisplayName</key><string>%s</string>\n' "$(xml_escape "$PROFILE_NAME")"
    printf '%s\n' '<key>PayloadDescription</key><string>Disables Apple Intelligence features and prevents selected model sets from being re-downloaded. Remove this profile to undo.</string>'
    printf '%s\n' '<key>PayloadOrganization</key><string>Apple AI remover</string>'
    printf '%s\n' '<key>PayloadScope</key><string>System</string>'
    printf '%s\n' '<key>PayloadRemovalDisallowed</key><false/>'
    printf '%s\n' '<key>PayloadContent</key><array>'

    payload_header com.apple.applicationaccess restrictions 'Apple Intelligence restrictions'
    printf '%s\n' '      <key>PayloadContent</key><dict>'
    for feature in "${FEATURES[@]}"; do
      kept "$feature" && continue
      while IFS= read -r key; do
        [[ -n "$key" ]] && printf '        <key>%s</key><false/>\n' "$(xml_escape "$key")"
      done < <(feature_restrictions "$feature")
    done
    printf '%s\n' '      </dict>' '    </dict>'

    for d in com.apple.assistant.support com.apple.Siri group.com.apple.mail group.com.apple.usernoted com.apple.MobileSMS .GlobalPreferences com.apple.spatialphotosrelive; do
      PREF_LINES=''
      while IFS=$'\t' read -r domain key value; do
        [[ "$domain" == "$d" ]] || continue
        PREF_LINES="${PREF_LINES}${key}"$'\t'"${value}"$'\n'
      done <<< "$ALL_PREFS"
      append_pref_payload "$d" "$d" "Forced settings: $d"
    done

    PREF_LINES=''
    while IFS=$'\t' read -r domain key value; do
      [[ "$domain" == 'com.apple.MobileAsset' ]] || continue
      PREF_LINES="${PREF_LINES}${key}"$'\t'"${value}"$'\n'
    done <<< "$ALL_PREFS"
    append_pref_payload com.apple.MobileAsset MobileAsset 'MobileAsset download overrides'

    PREF_LINES="installed"$'\t'true$'\n'"kept"$'\t'"$(keep_csv)"$'\n'
    append_pref_payload "$PROFILE_ID" marker 'Apple AI remover state'

    printf '%s\n' '</array></dict></plist>'
  } > "$tmp"
  /usr/bin/plutil -lint "$tmp" >/dev/null 2>&1 || { rm -f "$tmp"; fail 'generated profile failed plist validation'; }
  mv "$tmp" "$output"
}

keep_csv() {
  local out='' item
  for item in "${KEEP[@]}"; do
    [[ -n "$out" ]] && out="$out,"
    out="$out$item"
  done
  printf '%s' "$out"
}

helper_pref() { "$HELPER" pref "$1" "$2"; }
profile_installed() { local o; o="$(helper_pref "$PROFILE_ID" installed 2>/dev/null)" || return 1; [[ "$o" == *$'forced=1\tvalue=true'* ]]; }
legacy_profile_installed() { local o; o="$(helper_pref "$LEGACY_PROFILE_ID" installed 2>/dev/null)" || return 1; [[ "$o" == *$'forced=1\tvalue=true'* ]]; }
profile_kept_csv() { local o; o="$(helper_pref "$PROFILE_ID" kept 2>/dev/null)" || return 1; printf '%s' "${o#*value=}"; }

validate_uaf_catalog() {
  local set expected actual
  for set in "${MODEL_SETS[@]}"; do
    expected="$(model_set_asset_type "$set")"
    actual="$($HELPER asset-type "$set")" || fail "UAF asset-set lookup failed for $set"
    [[ "$actual" == "$expected" ]] || fail "UAF mapping mismatch for $set: expected $expected, got $actual"
  done
}

model_bytes() {
  local set="$1" out
  out="$($HELPER bytes "$set" 2>/dev/null)" || return 1
  [[ "$out" =~ ^[0-9]+$ ]] || return 1
  printf '%s' "$out"
}

format_bytes() {
  local b="$1"
  if (( b >= 1000000000 )); then awk -v n="$b" 'BEGIN { printf "%.1f GB", n/1e9 }'
  elif (( b > 0 )); then awk -v n="$b" 'BEGIN { printf "%.0f MB", n/1e6 }'
  else echo '0 MB'; fi
}

feature_state() {
  local feature="$1" domain key want output forced value
  local all=1 any=0
  while IFS=$'\t' read -r domain key want; do
    [[ -n "$domain" ]] || continue
    output="$(helper_pref "$domain" "$key" 2>/dev/null)" || { echo unknown; return; }
    forced="$(printf '%s' "$output" | sed -n 's/.*forced=\([^\t]*\).*/\1/p')"
    value="$(printf '%s' "$output" | sed -n 's/.*value=\([^\t]*\)$/\1/p')"
    [[ "$forced" == 1 && "$value" == "$want" ]] && any=1 || all=0
  done < <(feature_preferences "$feature")
  if (( all == 1 && any == 1 )); then echo locked; return; fi

  case "$feature" in
    chatgpt|writing-tools|genmoji|image-playground|safari-summaries|notes-summaries)
      local restricted_ok=1 r
      while IFS= read -r r; do
        [[ -n "$r" ]] || continue
        output="$(helper_pref com.apple.applicationaccess "$r" 2>/dev/null)" || { echo unknown; return; }
        [[ "$output" == *$'forced=1\tvalue=false'* ]] || restricted_ok=0
      done < <(feature_restrictions "$feature")
      (( restricted_ok == 1 )) && echo locked && return
      ;;
  esac

  if profile_installed && ! kept "$feature" && [[ -z "$(feature_preferences "$feature")" ]] && [[ -z "$(feature_restrictions "$feature")" ]]; then
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
  local feature state set n total=0
  for feature in "${FEATURES[@]}"; do
    state="$(feature_state "$feature")"
    printf '%-44s %s\n' "$(feature_title "$feature")" "$state"
  done
  printf '\nModels on disk\n'
  for set in "${MODEL_SETS[@]}"; do
    if n="$(model_bytes "$set")"; then
      total=$((total+n)); printf '  %-44s %s\n' "$(model_set_title "$set")" "$(format_bytes "$n")"
    else
      printf '  %-44s unknown\n' "$(model_set_title "$set")"
    fi
  done
  printf '  %-44s %s\n' Total "$(format_bytes "$total")"
  printf 'Profile: %s\n' "$(profile_installed && echo installed || echo not-installed)"
}

print_features() {
  local f
  for f in "${FEATURES[@]}"; do printf '%-28s %s\n' "$f" "$(feature_title "$f")"; done
}

open_profile_settings() {
  open 'x-apple.systempreferences:com.apple.Profiles-Settings.extension' 2>/dev/null || open 'x-apple.systempreferences:com.apple.preferences.configurationprofiles' 2>/dev/null || true
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
  printf 'Turn off Apple Intelligence and reset the selected models? [y/N] '
  read -r answer
  [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

off_command() {
  parse_args "$@"
  build_helper
  legacy_profile_installed && fail "legacy RemoveMacAI profile is installed; run '$0 revert' first"
  validate_uaf_catalog
  local sets
  sets="$(sets_to_remove)"

  printf 'Features to disable:\n'
  local f
  for f in "${FEATURES[@]}"; do kept "$f" || printf '  - %s\n' "$(feature_title "$f")"; done
  printf 'Model sets to reset:\n%s\n' "$(printf '%s\n' "$sets" | sed 's/^/  - /')"

  if (( DRY_RUN == 1 )); then
    local dry="${TMPDIR:-/tmp}/Apple-AI-remover.$$.mobileconfig"
    build_profile "$dry" "$sets"
    info 'DRY RUN: no profile was installed and no model was reset.'
    info "generated profile: $dry"
    return 0
  fi

  confirm || { info 'Nothing changed.'; return 0; }

  local expected
  expected="$(keep_csv)"
  build_profile "$PROFILE_FILE" "$sets"
  open "$PROFILE_FILE" 2>/dev/null || true
  open_profile_settings
  info "Approve '$PROFILE_NAME' in System Settings."
  wait_for_profile "$expected" || fail 'profile installation was not observed; no model reset was attempted'

  if [[ -n "$sets" ]]; then
    if reset_models "$sets"; then
      info 'All selected model sets reset successfully.'
    else
      fail 'profile is installed, but one or more model resets failed; run status to inspect remaining model state'
    fi
  fi
  info "Done. Run: $0 status"
}

revert_command() {
  build_helper
  local current=0 legacy=0
  profile_installed && current=1
  legacy_profile_installed && legacy=1
  if (( current == 0 && legacy == 0 )); then info 'No Apple AI remover profile is installed.'; return 0; fi
  if (( YES == 0 )); then
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
  local f set x saved_keep all a b
  for f in "${FEATURES[@]}"; do
    feature_title "$f" >/dev/null || fail "missing title for $f"
    while IFS= read -r x; do
      [[ -z "$x" ]] && continue
      model_set_asset_type "$x" >/dev/null || fail "unknown model set $x referenced by $f"
    done < <(feature_model_sets "$f")
  done
  for set in "${MODEL_SETS[@]}"; do model_set_asset_type "$set" >/dev/null || fail "missing model-set mapping $set"; done

  saved_keep=("${KEEP[@]}")
  KEEP=()
  all="$(sets_to_remove)"
  [[ "$(printf '%s\n' "$all" | sort)" == "$(printf '%s\n' "${MODEL_SETS[@]}" | sort)" ]] || fail 'empty keep set must remove every model set'

  KEEP=(writing-tools)
  all="$(sets_to_remove)"
  ! grep -qx 'com.apple.modelcatalog' <<< "$all" || fail 'writing-tools must protect foundation models'
  grep -qx 'com.apple.MobileAsset.UAF.FM.Visual' <<< "$all" || fail 'writing-tools unexpectedly protects visual models'
  KEEP=("${saved_keep[@]}")

  a="$(stable_uuid "$PROFILE_ID")"; b="$(stable_uuid "$PROFILE_ID")"; [[ "$a" == "$b" ]] || fail 'payload UUID generator is not stable'
  printf 'selftest: PASS (%s features, %s model sets)\n' "${#FEATURES[@]}" "${#MODEL_SETS[@]}"
}

usage() {
  cat <<EOF_USAGE
$PRODUCT_NAME $VERSION

Usage:
  $0 status
  $0 features
  $0 off [--keep feature[,feature...]] [--dry-run] [--yes]
  $0 revert [--yes]
  $0 selftest

The mutating commands target macOS $TARGET_MAJOR.x on Apple silicon.
EOF_USAGE
}

main() {
  local command="${1:-status}"
  shift || true
  case "$command" in
    status) require_platform; status_command "$@" ;;
    features) [[ "$#" -eq 0 ]] || fail 'features takes no options'; print_features ;;
    off) require_platform; off_command "$@" ;;
    revert) require_platform; parse_args "$@"; revert_command ;;
    selftest) [[ "$#" -eq 0 ]] || fail 'selftest takes no options'; selftest_command ;;
    --help|-h|help) usage ;;
    --version|-v|version) echo "$VERSION" ;;
    *) usage >&2; exit 1 ;;
  esac
}

main "$@"
\t'"${value}"
    [[ -n "$set" ]] || continue
    key="DownloadServerBaseURLOverride-$(model_set_asset_type "$set")"
    PREF_LINES="${PREF_LINES}com.apple.MobileAsset"$'\t'"${key}"$'\t'"${BLOCKED_URL}"$'\n'
  done <<< "$sets"

  mkdir -p "$(dirname "$output")"
  {
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
    printf '%s\n' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    printf '%s\n' '<plist version="1.0"><dict>'
    printf '%s\n' '<key>PayloadType</key><string>Configuration</string>'
    printf '%s\n' '<key>PayloadVersion</key><integer>1</integer>'
    printf '<key>PayloadIdentifier</key><string>%s</string>\n' "$PROFILE_ID"
    printf '<key>PayloadUUID</key><string>%s</string>\n' "$(stable_uuid "$PROFILE_ID")"
    printf '<key>PayloadDisplayName</key><string>%s</string>\n' "$(xml_escape "$PROFILE_NAME")"
    printf '%s\n' '<key>PayloadDescription</key><string>Disables Apple Intelligence features and prevents selected model sets from being re-downloaded. Remove this profile to undo.</string>'
    printf '%s\n' '<key>PayloadOrganization</key><string>Apple AI remover</string>'
    printf '%s\n' '<key>PayloadScope</key><string>System</string>'
    printf '%s\n' '<key>PayloadRemovalDisallowed</key><false/>'
    printf '%s\n' '<key>PayloadContent</key><array>'

    payload_header com.apple.applicationaccess restrictions 'Apple Intelligence restrictions'
    printf '%s\n' '      <key>PayloadContent</key><dict>'
    for feature in "${FEATURES[@]}"; do
      kept "$feature" && continue
      while IFS= read -r key; do
        [[ -n "$key" ]] && printf '        <key>%s</key><false/>\n' "$(xml_escape "$key")"
      done < <(feature_restrictions "$feature")
    done
    printf '%s\n' '      </dict>' '    </dict>'

    for d in com.apple.assistant.support com.apple.Siri group.com.apple.mail group.com.apple.usernoted com.apple.MobileSMS .GlobalPreferences com.apple.spatialphotosrelive; do
      PREF_LINES=''
      while IFS=$'\t' read -r domain key value; do
        [[ "$domain" == "$d" ]] || continue
        PREF_LINES="${PREF_LINES}${key}"$'\t'"${value}"$'\n'
      done <<< "$ALL_PREFS"
      append_pref_payload "$d" "$d" "Forced settings: $d"
    done

    PREF_LINES=''
    while IFS=$'\t' read -r domain key value; do
      [[ "$domain" == 'com.apple.MobileAsset' ]] || continue
      PREF_LINES="${PREF_LINES}${key}"$'\t'"${value}"$'\n'
    done <<< "$ALL_PREFS"
    append_pref_payload com.apple.MobileAsset MobileAsset 'MobileAsset download overrides'

    PREF_LINES="installed"$'\t'true$'\n'"kept"$'\t'"$(keep_csv)"$'\n'
    append_pref_payload "$PROFILE_ID" marker 'Apple AI remover state'

    printf '%s\n' '</array></dict></plist>'
  } > "$tmp"
  /usr/bin/plutil -lint "$tmp" >/dev/null 2>&1 || { rm -f "$tmp"; fail 'generated profile failed plist validation'; }
  mv "$tmp" "$output"
}

keep_csv() {
  local out='' item
  for item in "${KEEP[@]}"; do
    [[ -n "$out" ]] && out="$out,"
    out="$out$item"
  done
  printf '%s' "$out"
}

helper_pref() { "$HELPER" pref "$1" "$2"; }
profile_installed() { local o; o="$(helper_pref "$PROFILE_ID" installed 2>/dev/null)" || return 1; [[ "$o" == *$'forced=1\tvalue=true'* ]]; }
legacy_profile_installed() { local o; o="$(helper_pref "$LEGACY_PROFILE_ID" installed 2>/dev/null)" || return 1; [[ "$o" == *$'forced=1\tvalue=true'* ]]; }
profile_kept_csv() { local o; o="$(helper_pref "$PROFILE_ID" kept 2>/dev/null)" || return 1; printf '%s' "${o#*value=}"; }

validate_uaf_catalog() {
  local set expected actual
  for set in "${MODEL_SETS[@]}"; do
    expected="$(model_set_asset_type "$set")"
    actual="$($HELPER asset-type "$set")" || fail "UAF asset-set lookup failed for $set"
    [[ "$actual" == "$expected" ]] || fail "UAF mapping mismatch for $set: expected $expected, got $actual"
  done
}

model_bytes() {
  local set="$1" out
  out="$($HELPER bytes "$set" 2>/dev/null)" || return 1
  [[ "$out" =~ ^[0-9]+$ ]] || return 1
  printf '%s' "$out"
}

format_bytes() {
  local b="$1"
  if (( b >= 1000000000 )); then awk -v n="$b" 'BEGIN { printf "%.1f GB", n/1e9 }'
  elif (( b > 0 )); then awk -v n="$b" 'BEGIN { printf "%.0f MB", n/1e6 }'
  else echo '0 MB'; fi
}

feature_state() {
  local feature="$1" domain key want output forced value
  local all=1 any=0
  while IFS=$'\t' read -r domain key want; do
    [[ -n "$domain" ]] || continue
    output="$(helper_pref "$domain" "$key" 2>/dev/null)" || { echo unknown; return; }
    forced="$(printf '%s' "$output" | sed -n 's/.*forced=\([^\t]*\).*/\1/p')"
    value="$(printf '%s' "$output" | sed -n 's/.*value=\([^\t]*\)$/\1/p')"
    [[ "$forced" == 1 && "$value" == "$want" ]] && any=1 || all=0
  done < <(feature_preferences "$feature")
  if (( all == 1 && any == 1 )); then echo locked; return; fi

  case "$feature" in
    chatgpt|writing-tools|genmoji|image-playground|safari-summaries|notes-summaries)
      local restricted_ok=1 r
      while IFS= read -r r; do
        [[ -n "$r" ]] || continue
        output="$(helper_pref com.apple.applicationaccess "$r" 2>/dev/null)" || { echo unknown; return; }
        [[ "$output" == *$'forced=1\tvalue=false'* ]] || restricted_ok=0
      done < <(feature_restrictions "$feature")
      (( restricted_ok == 1 )) && echo locked && return
      ;;
  esac

  if profile_installed && ! kept "$feature" && [[ -z "$(feature_preferences "$feature")" ]] && [[ -z "$(feature_restrictions "$feature")" ]]; then
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
  local feature state set n total=0
  for feature in "${FEATURES[@]}"; do
    state="$(feature_state "$feature")"
    printf '%-44s %s\n' "$(feature_title "$feature")" "$state"
  done
  printf '\nModels on disk\n'
  for set in "${MODEL_SETS[@]}"; do
    if n="$(model_bytes "$set")"; then
      total=$((total+n)); printf '  %-44s %s\n' "$(model_set_title "$set")" "$(format_bytes "$n")"
    else
      printf '  %-44s unknown\n' "$(model_set_title "$set")"
    fi
  done
  printf '  %-44s %s\n' Total "$(format_bytes "$total")"
  printf 'Profile: %s\n' "$(profile_installed && echo installed || echo not-installed)"
}

print_features() {
  local f
  for f in "${FEATURES[@]}"; do printf '%-28s %s\n' "$f" "$(feature_title "$f")"; done
}

open_profile_settings() {
  open 'x-apple.systempreferences:com.apple.Profiles-Settings.extension' 2>/dev/null || open 'x-apple.systempreferences:com.apple.preferences.configurationprofiles' 2>/dev/null || true
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
  printf 'Turn off Apple Intelligence and reset the selected models? [y/N] '
  read -r answer
  [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

off_command() {
  parse_args "$@"
  build_helper
  legacy_profile_installed && fail "legacy RemoveMacAI profile is installed; run '$0 revert' first"
  validate_uaf_catalog
  local sets
  sets="$(sets_to_remove)"

  printf 'Features to disable:\n'
  local f
  for f in "${FEATURES[@]}"; do kept "$f" || printf '  - %s\n' "$(feature_title "$f")"; done
  printf 'Model sets to reset:\n%s\n' "$(printf '%s\n' "$sets" | sed 's/^/  - /')"

  if (( DRY_RUN == 1 )); then
    local dry="${TMPDIR:-/tmp}/Apple-AI-remover.$$.mobileconfig"
    build_profile "$dry" "$sets"
    info 'DRY RUN: no profile was installed and no model was reset.'
    info "generated profile: $dry"
    return 0
  fi

  confirm || { info 'Nothing changed.'; return 0; }

  local expected
  expected="$(keep_csv)"
  build_profile "$PROFILE_FILE" "$sets"
  open "$PROFILE_FILE" 2>/dev/null || true
  open_profile_settings
  info "Approve '$PROFILE_NAME' in System Settings."
  wait_for_profile "$expected" || fail 'profile installation was not observed; no model reset was attempted'

  if [[ -n "$sets" ]]; then
    if reset_models "$sets"; then
      info 'All selected model sets reset successfully.'
    else
      fail 'profile is installed, but one or more model resets failed; run status to inspect remaining model state'
    fi
  fi
  info "Done. Run: $0 status"
}

revert_command() {
  build_helper
  local current=0 legacy=0
  profile_installed && current=1
  legacy_profile_installed && legacy=1
  if (( current == 0 && legacy == 0 )); then info 'No Apple AI remover profile is installed.'; return 0; fi
  if (( YES == 0 )); then
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
  local f set x saved_keep all a b
  for f in "${FEATURES[@]}"; do
    feature_title "$f" >/dev/null || fail "missing title for $f"
    while IFS= read -r x; do
      [[ -z "$x" ]] && continue
      model_set_asset_type "$x" >/dev/null || fail "unknown model set $x referenced by $f"
    done < <(feature_model_sets "$f")
  done
  for set in "${MODEL_SETS[@]}"; do model_set_asset_type "$set" >/dev/null || fail "missing model-set mapping $set"; done

  saved_keep=("${KEEP[@]}")
  KEEP=()
  all="$(sets_to_remove)"
  [[ "$(printf '%s\n' "$all" | sort)" == "$(printf '%s\n' "${MODEL_SETS[@]}" | sort)" ]] || fail 'empty keep set must remove every model set'

  KEEP=(writing-tools)
  all="$(sets_to_remove)"
  ! grep -qx 'com.apple.modelcatalog' <<< "$all" || fail 'writing-tools must protect foundation models'
  grep -qx 'com.apple.MobileAsset.UAF.FM.Visual' <<< "$all" || fail 'writing-tools unexpectedly protects visual models'
  KEEP=("${saved_keep[@]}")

  a="$(stable_uuid "$PROFILE_ID")"; b="$(stable_uuid "$PROFILE_ID")"; [[ "$a" == "$b" ]] || fail 'payload UUID generator is not stable'
  printf 'selftest: PASS (%s features, %s model sets)\n' "${#FEATURES[@]}" "${#MODEL_SETS[@]}"
}

usage() {
  cat <<EOF_USAGE
$PRODUCT_NAME $VERSION

Usage:
  $0 status
  $0 features
  $0 off [--keep feature[,feature...]] [--dry-run] [--yes]
  $0 revert [--yes]
  $0 selftest

The mutating commands target macOS $TARGET_MAJOR.x on Apple silicon.
EOF_USAGE
}

main() {
  local command="${1:-status}"
  shift || true
  case "$command" in
    status) require_platform; status_command "$@" ;;
    features) [[ "$#" -eq 0 ]] || fail 'features takes no options'; print_features ;;
    off) require_platform; off_command "$@" ;;
    revert) require_platform; parse_args "$@"; revert_command ;;
    selftest) [[ "$#" -eq 0 ]] || fail 'selftest takes no options'; selftest_command ;;
    --help|-h|help) usage ;;
    --version|-v|version) echo "$VERSION" ;;
    *) usage >&2; exit 1 ;;
  esac
}

main "$@"
\n'
    done < <(feature_preferences "$feature")
  done
  while IFS= read -r set; do
    [[ -n "$set" ]] || continue
    key="DownloadServerBaseURLOverride-$(model_set_asset_type "$set")"
    PREF_LINES="${PREF_LINES}com.apple.MobileAsset"$'\t'"${key}"$'\t'"${BLOCKED_URL}"$'\n'
  done <<< "$sets"

  mkdir -p "$(dirname "$output")"
  {
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
    printf '%s\n' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    printf '%s\n' '<plist version="1.0"><dict>'
    printf '%s\n' '<key>PayloadType</key><string>Configuration</string>'
    printf '%s\n' '<key>PayloadVersion</key><integer>1</integer>'
    printf '<key>PayloadIdentifier</key><string>%s</string>\n' "$PROFILE_ID"
    printf '<key>PayloadUUID</key><string>%s</string>\n' "$(stable_uuid "$PROFILE_ID")"
    printf '<key>PayloadDisplayName</key><string>%s</string>\n' "$(xml_escape "$PROFILE_NAME")"
    printf '%s\n' '<key>PayloadDescription</key><string>Disables Apple Intelligence features and prevents selected model sets from being re-downloaded. Remove this profile to undo.</string>'
    printf '%s\n' '<key>PayloadOrganization</key><string>Apple AI remover</string>'
    printf '%s\n' '<key>PayloadScope</key><string>System</string>'
    printf '%s\n' '<key>PayloadRemovalDisallowed</key><false/>'
    printf '%s\n' '<key>PayloadContent</key><array>'

    payload_header com.apple.applicationaccess restrictions 'Apple Intelligence restrictions'
    printf '%s\n' '      <key>PayloadContent</key><dict>'
    for feature in "${FEATURES[@]}"; do
      kept "$feature" && continue
      while IFS= read -r key; do
        [[ -n "$key" ]] && printf '        <key>%s</key><false/>\n' "$(xml_escape "$key")"
      done < <(feature_restrictions "$feature")
    done
    printf '%s\n' '      </dict>' '    </dict>'

    for d in com.apple.assistant.support com.apple.Siri group.com.apple.mail group.com.apple.usernoted com.apple.MobileSMS .GlobalPreferences com.apple.spatialphotosrelive; do
      PREF_LINES=''
      while IFS=$'\t' read -r domain key value; do
        [[ "$domain" == "$d" ]] || continue
        PREF_LINES="${PREF_LINES}${key}"$'\t'"${value}"$'\n'
      done <<< "$ALL_PREFS"
      append_pref_payload "$d" "$d" "Forced settings: $d"
    done

    PREF_LINES=''
    while IFS=$'\t' read -r domain key value; do
      [[ "$domain" == 'com.apple.MobileAsset' ]] || continue
      PREF_LINES="${PREF_LINES}${key}"$'\t'"${value}"$'\n'
    done <<< "$ALL_PREFS"
    append_pref_payload com.apple.MobileAsset MobileAsset 'MobileAsset download overrides'

    PREF_LINES="installed"$'\t'true$'\n'"kept"$'\t'"$(keep_csv)"$'\n'
    append_pref_payload "$PROFILE_ID" marker 'Apple AI remover state'

    printf '%s\n' '</array></dict></plist>'
  } > "$tmp"
  /usr/bin/plutil -lint "$tmp" >/dev/null 2>&1 || { rm -f "$tmp"; fail 'generated profile failed plist validation'; }
  mv "$tmp" "$output"
}

keep_csv() {
  local out='' item
  for item in "${KEEP[@]}"; do
    [[ -n "$out" ]] && out="$out,"
    out="$out$item"
  done
  printf '%s' "$out"
}

helper_pref() { "$HELPER" pref "$1" "$2"; }
profile_installed() { local o; o="$(helper_pref "$PROFILE_ID" installed 2>/dev/null)" || return 1; [[ "$o" == *$'forced=1\tvalue=true'* ]]; }
legacy_profile_installed() { local o; o="$(helper_pref "$LEGACY_PROFILE_ID" installed 2>/dev/null)" || return 1; [[ "$o" == *$'forced=1\tvalue=true'* ]]; }
profile_kept_csv() { local o; o="$(helper_pref "$PROFILE_ID" kept 2>/dev/null)" || return 1; printf '%s' "${o#*value=}"; }

validate_uaf_catalog() {
  local set expected actual
  for set in "${MODEL_SETS[@]}"; do
    expected="$(model_set_asset_type "$set")"
    actual="$($HELPER asset-type "$set")" || fail "UAF asset-set lookup failed for $set"
    [[ "$actual" == "$expected" ]] || fail "UAF mapping mismatch for $set: expected $expected, got $actual"
  done
}

model_bytes() {
  local set="$1" out
  out="$($HELPER bytes "$set" 2>/dev/null)" || return 1
  [[ "$out" =~ ^[0-9]+$ ]] || return 1
  printf '%s' "$out"
}

format_bytes() {
  local b="$1"
  if (( b >= 1000000000 )); then awk -v n="$b" 'BEGIN { printf "%.1f GB", n/1e9 }'
  elif (( b > 0 )); then awk -v n="$b" 'BEGIN { printf "%.0f MB", n/1e6 }'
  else echo '0 MB'; fi
}

feature_state() {
  local feature="$1" domain key want output forced value
  local all=1 any=0
  while IFS=$'\t' read -r domain key want; do
    [[ -n "$domain" ]] || continue
    output="$(helper_pref "$domain" "$key" 2>/dev/null)" || { echo unknown; return; }
    forced="$(printf '%s' "$output" | sed -n 's/.*forced=\([^\t]*\).*/\1/p')"
    value="$(printf '%s' "$output" | sed -n 's/.*value=\([^\t]*\)$/\1/p')"
    [[ "$forced" == 1 && "$value" == "$want" ]] && any=1 || all=0
  done < <(feature_preferences "$feature")
  if (( all == 1 && any == 1 )); then echo locked; return; fi

  case "$feature" in
    chatgpt|writing-tools|genmoji|image-playground|safari-summaries|notes-summaries)
      local restricted_ok=1 r
      while IFS= read -r r; do
        [[ -n "$r" ]] || continue
        output="$(helper_pref com.apple.applicationaccess "$r" 2>/dev/null)" || { echo unknown; return; }
        [[ "$output" == *$'forced=1\tvalue=false'* ]] || restricted_ok=0
      done < <(feature_restrictions "$feature")
      (( restricted_ok == 1 )) && echo locked && return
      ;;
  esac

  if profile_installed && ! kept "$feature" && [[ -z "$(feature_preferences "$feature")" ]] && [[ -z "$(feature_restrictions "$feature")" ]]; then
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
  local feature state set n total=0
  for feature in "${FEATURES[@]}"; do
    state="$(feature_state "$feature")"
    printf '%-44s %s\n' "$(feature_title "$feature")" "$state"
  done
  printf '\nModels on disk\n'
  for set in "${MODEL_SETS[@]}"; do
    if n="$(model_bytes "$set")"; then
      total=$((total+n)); printf '  %-44s %s\n' "$(model_set_title "$set")" "$(format_bytes "$n")"
    else
      printf '  %-44s unknown\n' "$(model_set_title "$set")"
    fi
  done
  printf '  %-44s %s\n' Total "$(format_bytes "$total")"
  printf 'Profile: %s\n' "$(profile_installed && echo installed || echo not-installed)"
}

print_features() {
  local f
  for f in "${FEATURES[@]}"; do printf '%-28s %s\n' "$f" "$(feature_title "$f")"; done
}

open_profile_settings() {
  open 'x-apple.systempreferences:com.apple.Profiles-Settings.extension' 2>/dev/null || open 'x-apple.systempreferences:com.apple.preferences.configurationprofiles' 2>/dev/null || true
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
  printf 'Turn off Apple Intelligence and reset the selected models? [y/N] '
  read -r answer
  [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

off_command() {
  parse_args "$@"
  build_helper
  legacy_profile_installed && fail "legacy RemoveMacAI profile is installed; run '$0 revert' first"
  validate_uaf_catalog
  local sets
  sets="$(sets_to_remove)"

  printf 'Features to disable:\n'
  local f
  for f in "${FEATURES[@]}"; do kept "$f" || printf '  - %s\n' "$(feature_title "$f")"; done
  printf 'Model sets to reset:\n%s\n' "$(printf '%s\n' "$sets" | sed 's/^/  - /')"

  if (( DRY_RUN == 1 )); then
    local dry="${TMPDIR:-/tmp}/Apple-AI-remover.$$.mobileconfig"
    build_profile "$dry" "$sets"
    info 'DRY RUN: no profile was installed and no model was reset.'
    info "generated profile: $dry"
    return 0
  fi

  confirm || { info 'Nothing changed.'; return 0; }

  local expected
  expected="$(keep_csv)"
  build_profile "$PROFILE_FILE" "$sets"
  open "$PROFILE_FILE" 2>/dev/null || true
  open_profile_settings
  info "Approve '$PROFILE_NAME' in System Settings."
  wait_for_profile "$expected" || fail 'profile installation was not observed; no model reset was attempted'

  if [[ -n "$sets" ]]; then
    if reset_models "$sets"; then
      info 'All selected model sets reset successfully.'
    else
      fail 'profile is installed, but one or more model resets failed; run status to inspect remaining model state'
    fi
  fi
  info "Done. Run: $0 status"
}

revert_command() {
  build_helper
  local current=0 legacy=0
  profile_installed && current=1
  legacy_profile_installed && legacy=1
  if (( current == 0 && legacy == 0 )); then info 'No Apple AI remover profile is installed.'; return 0; fi
  if (( YES == 0 )); then
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
  local f set x saved_keep all a b
  for f in "${FEATURES[@]}"; do
    feature_title "$f" >/dev/null || fail "missing title for $f"
    while IFS= read -r x; do
      [[ -z "$x" ]] && continue
      model_set_asset_type "$x" >/dev/null || fail "unknown model set $x referenced by $f"
    done < <(feature_model_sets "$f")
  done
  for set in "${MODEL_SETS[@]}"; do model_set_asset_type "$set" >/dev/null || fail "missing model-set mapping $set"; done

  saved_keep=("${KEEP[@]}")
  KEEP=()
  all="$(sets_to_remove)"
  [[ "$(printf '%s\n' "$all" | sort)" == "$(printf '%s\n' "${MODEL_SETS[@]}" | sort)" ]] || fail 'empty keep set must remove every model set'

  KEEP=(writing-tools)
  all="$(sets_to_remove)"
  ! grep -qx 'com.apple.modelcatalog' <<< "$all" || fail 'writing-tools must protect foundation models'
  grep -qx 'com.apple.MobileAsset.UAF.FM.Visual' <<< "$all" || fail 'writing-tools unexpectedly protects visual models'
  KEEP=("${saved_keep[@]}")

  a="$(stable_uuid "$PROFILE_ID")"; b="$(stable_uuid "$PROFILE_ID")"; [[ "$a" == "$b" ]] || fail 'payload UUID generator is not stable'
  printf 'selftest: PASS (%s features, %s model sets)\n' "${#FEATURES[@]}" "${#MODEL_SETS[@]}"
}

usage() {
  cat <<EOF_USAGE
$PRODUCT_NAME $VERSION

Usage:
  $0 status
  $0 features
  $0 off [--keep feature[,feature...]] [--dry-run] [--yes]
  $0 revert [--yes]
  $0 selftest

The mutating commands target macOS $TARGET_MAJOR.x on Apple silicon.
EOF_USAGE
}

main() {
  local command="${1:-status}"
  shift || true
  case "$command" in
    status) require_platform; status_command "$@" ;;
    features) [[ "$#" -eq 0 ]] || fail 'features takes no options'; print_features ;;
    off) require_platform; off_command "$@" ;;
    revert) require_platform; parse_args "$@"; revert_command ;;
    selftest) [[ "$#" -eq 0 ]] || fail 'selftest takes no options'; selftest_command ;;
    --help|-h|help) usage ;;
    --version|-v|version) echo "$VERSION" ;;
    *) usage >&2; exit 1 ;;
  esac
}

main "$@"
forced=1\tvalue=true'* ]]; }
profile_kept_csv() { local o; o="$(helper_pref "$PROFILE_ID" kept 2>/dev/null)" || return 1; printf '%s' "${o#*value=}"; }

validate_uaf_catalog() {
  local set expected actual
  for set in "${MODEL_SETS[@]}"; do
    expected="$(model_set_asset_type "$set")"
    actual="$($HELPER asset-type "$set")" || fail "UAF asset-set lookup failed for $set"
    [[ "$actual" == "$expected" ]] || fail "UAF mapping mismatch for $set: expected $expected, got $actual"
  done
}

model_bytes() {
  local set="$1" out
  out="$($HELPER bytes "$set" 2>/dev/null)" || return 1
  [[ "$out" =~ ^[0-9]+$ ]] || return 1
  printf '%s' "$out"
}

format_bytes() {
  local b="$1"
  if (( b >= 1000000000 )); then awk -v n="$b" 'BEGIN { printf "%.1f GB", n/1e9 }'
  elif (( b > 0 )); then awk -v n="$b" 'BEGIN { printf "%.0f MB", n/1e6 }'
  else echo '0 MB'; fi
}

feature_state() {
  local feature="$1" domain key want output forced value
  local all=1 any=0
  while IFS=$'\t' read -r domain key want; do
    [[ -n "$domain" ]] || continue
    output="$(helper_pref "$domain" "$key" 2>/dev/null)" || { echo unknown; return; }
    forced="$(printf '%s' "$output" | sed -n 's/.*forced=\([^\t]*\).*/\1/p')"
    value="$(printf '%s' "$output" | sed -n 's/.*value=\([^\t]*\)$/\1/p')"
    [[ "$forced" == 1 && "$value" == "$want" ]] && any=1 || all=0
  done < <(feature_preferences "$feature")
  if (( all == 1 && any == 1 )); then echo locked; return; fi

  case "$feature" in
    chatgpt|writing-tools|genmoji|image-playground|safari-summaries|notes-summaries)
      local restricted_ok=1 r
      while IFS= read -r r; do
        [[ -n "$r" ]] || continue
        output="$(helper_pref com.apple.applicationaccess "$r" 2>/dev/null)" || { echo unknown; return; }
        [[ "$output" == *$'forced=1\tvalue=false'* ]] || restricted_ok=0
      done < <(feature_restrictions "$feature")
      (( restricted_ok == 1 )) && echo locked && return
      ;;
  esac

  if profile_installed && ! kept "$feature" && [[ -z "$(feature_preferences "$feature")" ]] && [[ -z "$(feature_restrictions "$feature")" ]]; then
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
  local feature state set n total=0
  for feature in "${FEATURES[@]}"; do
    state="$(feature_state "$feature")"
    printf '%-44s %s\n' "$(feature_title "$feature")" "$state"
  done
  printf '\nModels on disk\n'
  for set in "${MODEL_SETS[@]}"; do
    if n="$(model_bytes "$set")"; then
      total=$((total+n)); printf '  %-44s %s\n' "$(model_set_title "$set")" "$(format_bytes "$n")"
    else
      printf '  %-44s unknown\n' "$(model_set_title "$set")"
    fi
  done
  printf '  %-44s %s\n' Total "$(format_bytes "$total")"
  printf 'Profile: %s\n' "$(profile_installed && echo installed || echo not-installed)"
}

print_features() {
  local f
  for f in "${FEATURES[@]}"; do printf '%-28s %s\n' "$f" "$(feature_title "$f")"; done
}

open_profile_settings() {
  open 'x-apple.systempreferences:com.apple.Profiles-Settings.extension' 2>/dev/null || open 'x-apple.systempreferences:com.apple.preferences.configurationprofiles' 2>/dev/null || true
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
  printf 'Turn off Apple Intelligence and reset the selected models? [y/N] '
  read -r answer
  [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

off_command() {
  parse_args "$@"
  build_helper
  legacy_profile_installed && fail "legacy RemoveMacAI profile is installed; run '$0 revert' first"
  validate_uaf_catalog
  local sets
  sets="$(sets_to_remove)"

  printf 'Features to disable:\n'
  local f
  for f in "${FEATURES[@]}"; do kept "$f" || printf '  - %s\n' "$(feature_title "$f")"; done
  printf 'Model sets to reset:\n%s\n' "$(printf '%s\n' "$sets" | sed 's/^/  - /')"

  if (( DRY_RUN == 1 )); then
    local dry="${TMPDIR:-/tmp}/Apple-AI-remover.$$.mobileconfig"
    build_profile "$dry" "$sets"
    info 'DRY RUN: no profile was installed and no model was reset.'
    info "generated profile: $dry"
    return 0
  fi

  confirm || { info 'Nothing changed.'; return 0; }

  local expected
  expected="$(keep_csv)"
  build_profile "$PROFILE_FILE" "$sets"
  open "$PROFILE_FILE" 2>/dev/null || true
  open_profile_settings
  info "Approve '$PROFILE_NAME' in System Settings."
  wait_for_profile "$expected" || fail 'profile installation was not observed; no model reset was attempted'

  if [[ -n "$sets" ]]; then
    if reset_models "$sets"; then
      info 'All selected model sets reset successfully.'
    else
      fail 'profile is installed, but one or more model resets failed; run status to inspect remaining model state'
    fi
  fi
  info "Done. Run: $0 status"
}

revert_command() {
  build_helper
  local current=0 legacy=0
  profile_installed && current=1
  legacy_profile_installed && legacy=1
  if (( current == 0 && legacy == 0 )); then info 'No Apple AI remover profile is installed.'; return 0; fi
  if (( YES == 0 )); then
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
  local f set x saved_keep all a b
  for f in "${FEATURES[@]}"; do
    feature_title "$f" >/dev/null || fail "missing title for $f"
    while IFS= read -r x; do
      [[ -z "$x" ]] && continue
      model_set_asset_type "$x" >/dev/null || fail "unknown model set $x referenced by $f"
    done < <(feature_model_sets "$f")
  done
  for set in "${MODEL_SETS[@]}"; do model_set_asset_type "$set" >/dev/null || fail "missing model-set mapping $set"; done

  saved_keep=("${KEEP[@]}")
  KEEP=()
  all="$(sets_to_remove)"
  [[ "$(printf '%s\n' "$all" | sort)" == "$(printf '%s\n' "${MODEL_SETS[@]}" | sort)" ]] || fail 'empty keep set must remove every model set'

  KEEP=(writing-tools)
  all="$(sets_to_remove)"
  ! grep -qx 'com.apple.modelcatalog' <<< "$all" || fail 'writing-tools must protect foundation models'
  grep -qx 'com.apple.MobileAsset.UAF.FM.Visual' <<< "$all" || fail 'writing-tools unexpectedly protects visual models'
  KEEP=("${saved_keep[@]}")

  a="$(stable_uuid "$PROFILE_ID")"; b="$(stable_uuid "$PROFILE_ID")"; [[ "$a" == "$b" ]] || fail 'payload UUID generator is not stable'
  printf 'selftest: PASS (%s features, %s model sets)\n' "${#FEATURES[@]}" "${#MODEL_SETS[@]}"
}

usage() {
  cat <<EOF_USAGE
$PRODUCT_NAME $VERSION

Usage:
  $0 status
  $0 features
  $0 off [--keep feature[,feature...]] [--dry-run] [--yes]
  $0 revert [--yes]
  $0 selftest

The mutating commands target macOS $TARGET_MAJOR.x on Apple silicon.
EOF_USAGE
}

main() {
  local command="${1:-status}"
  shift || true
  case "$command" in
    status) require_platform; status_command "$@" ;;
    features) [[ "$#" -eq 0 ]] || fail 'features takes no options'; print_features ;;
    off) require_platform; off_command "$@" ;;
    revert) require_platform; parse_args "$@"; revert_command ;;
    selftest) [[ "$#" -eq 0 ]] || fail 'selftest takes no options'; selftest_command ;;
    --help|-h|help) usage ;;
    --version|-v|version) echo "$VERSION" ;;
    *) usage >&2; exit 1 ;;
  esac
}

main "$@"
\t'"${key}"
    [[ -n "$set" ]] || continue
    key="DownloadServerBaseURLOverride-$(model_set_asset_type "$set")"
    PREF_LINES="${PREF_LINES}com.apple.MobileAsset"$'\t'"${key}"$'\t'"${BLOCKED_URL}"$'\n'
  done <<< "$sets"

  mkdir -p "$(dirname "$output")"
  {
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
    printf '%s\n' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    printf '%s\n' '<plist version="1.0"><dict>'
    printf '%s\n' '<key>PayloadType</key><string>Configuration</string>'
    printf '%s\n' '<key>PayloadVersion</key><integer>1</integer>'
    printf '<key>PayloadIdentifier</key><string>%s</string>\n' "$PROFILE_ID"
    printf '<key>PayloadUUID</key><string>%s</string>\n' "$(stable_uuid "$PROFILE_ID")"
    printf '<key>PayloadDisplayName</key><string>%s</string>\n' "$(xml_escape "$PROFILE_NAME")"
    printf '%s\n' '<key>PayloadDescription</key><string>Disables Apple Intelligence features and prevents selected model sets from being re-downloaded. Remove this profile to undo.</string>'
    printf '%s\n' '<key>PayloadOrganization</key><string>Apple AI remover</string>'
    printf '%s\n' '<key>PayloadScope</key><string>System</string>'
    printf '%s\n' '<key>PayloadRemovalDisallowed</key><false/>'
    printf '%s\n' '<key>PayloadContent</key><array>'

    payload_header com.apple.applicationaccess restrictions 'Apple Intelligence restrictions'
    printf '%s\n' '      <key>PayloadContent</key><dict>'
    for feature in "${FEATURES[@]}"; do
      kept "$feature" && continue
      while IFS= read -r key; do
        [[ -n "$key" ]] && printf '        <key>%s</key><false/>\n' "$(xml_escape "$key")"
      done < <(feature_restrictions "$feature")
    done
    printf '%s\n' '      </dict>' '    </dict>'

    for d in com.apple.assistant.support com.apple.Siri group.com.apple.mail group.com.apple.usernoted com.apple.MobileSMS .GlobalPreferences com.apple.spatialphotosrelive; do
      PREF_LINES=''
      while IFS=$'\t' read -r domain key value; do
        [[ "$domain" == "$d" ]] || continue
        PREF_LINES="${PREF_LINES}${key}"$'\t'"${value}"$'\n'
      done <<< "$ALL_PREFS"
      append_pref_payload "$d" "$d" "Forced settings: $d"
    done

    PREF_LINES=''
    while IFS=$'\t' read -r domain key value; do
      [[ "$domain" == 'com.apple.MobileAsset' ]] || continue
      PREF_LINES="${PREF_LINES}${key}"$'\t'"${value}"$'\n'
    done <<< "$ALL_PREFS"
    append_pref_payload com.apple.MobileAsset MobileAsset 'MobileAsset download overrides'

    PREF_LINES="installed"$'\t'true$'\n'"kept"$'\t'"$(keep_csv)"$'\n'
    append_pref_payload "$PROFILE_ID" marker 'Apple AI remover state'

    printf '%s\n' '</array></dict></plist>'
  } > "$tmp"
  /usr/bin/plutil -lint "$tmp" >/dev/null 2>&1 || { rm -f "$tmp"; fail 'generated profile failed plist validation'; }
  mv "$tmp" "$output"
}

keep_csv() {
  local out='' item
  for item in "${KEEP[@]}"; do
    [[ -n "$out" ]] && out="$out,"
    out="$out$item"
  done
  printf '%s' "$out"
}

helper_pref() { "$HELPER" pref "$1" "$2"; }
profile_installed() { local o; o="$(helper_pref "$PROFILE_ID" installed 2>/dev/null)" || return 1; [[ "$o" == *$'forced=1\tvalue=true'* ]]; }
legacy_profile_installed() { local o; o="$(helper_pref "$LEGACY_PROFILE_ID" installed 2>/dev/null)" || return 1; [[ "$o" == *$'forced=1\tvalue=true'* ]]; }
profile_kept_csv() { local o; o="$(helper_pref "$PROFILE_ID" kept 2>/dev/null)" || return 1; printf '%s' "${o#*value=}"; }

validate_uaf_catalog() {
  local set expected actual
  for set in "${MODEL_SETS[@]}"; do
    expected="$(model_set_asset_type "$set")"
    actual="$($HELPER asset-type "$set")" || fail "UAF asset-set lookup failed for $set"
    [[ "$actual" == "$expected" ]] || fail "UAF mapping mismatch for $set: expected $expected, got $actual"
  done
}

model_bytes() {
  local set="$1" out
  out="$($HELPER bytes "$set" 2>/dev/null)" || return 1
  [[ "$out" =~ ^[0-9]+$ ]] || return 1
  printf '%s' "$out"
}

format_bytes() {
  local b="$1"
  if (( b >= 1000000000 )); then awk -v n="$b" 'BEGIN { printf "%.1f GB", n/1e9 }'
  elif (( b > 0 )); then awk -v n="$b" 'BEGIN { printf "%.0f MB", n/1e6 }'
  else echo '0 MB'; fi
}

feature_state() {
  local feature="$1" domain key want output forced value
  local all=1 any=0
  while IFS=$'\t' read -r domain key want; do
    [[ -n "$domain" ]] || continue
    output="$(helper_pref "$domain" "$key" 2>/dev/null)" || { echo unknown; return; }
    forced="$(printf '%s' "$output" | sed -n 's/.*forced=\([^\t]*\).*/\1/p')"
    value="$(printf '%s' "$output" | sed -n 's/.*value=\([^\t]*\)$/\1/p')"
    [[ "$forced" == 1 && "$value" == "$want" ]] && any=1 || all=0
  done < <(feature_preferences "$feature")
  if (( all == 1 && any == 1 )); then echo locked; return; fi

  case "$feature" in
    chatgpt|writing-tools|genmoji|image-playground|safari-summaries|notes-summaries)
      local restricted_ok=1 r
      while IFS= read -r r; do
        [[ -n "$r" ]] || continue
        output="$(helper_pref com.apple.applicationaccess "$r" 2>/dev/null)" || { echo unknown; return; }
        [[ "$output" == *$'forced=1\tvalue=false'* ]] || restricted_ok=0
      done < <(feature_restrictions "$feature")
      (( restricted_ok == 1 )) && echo locked && return
      ;;
  esac

  if profile_installed && ! kept "$feature" && [[ -z "$(feature_preferences "$feature")" ]] && [[ -z "$(feature_restrictions "$feature")" ]]; then
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
  local feature state set n total=0
  for feature in "${FEATURES[@]}"; do
    state="$(feature_state "$feature")"
    printf '%-44s %s\n' "$(feature_title "$feature")" "$state"
  done
  printf '\nModels on disk\n'
  for set in "${MODEL_SETS[@]}"; do
    if n="$(model_bytes "$set")"; then
      total=$((total+n)); printf '  %-44s %s\n' "$(model_set_title "$set")" "$(format_bytes "$n")"
    else
      printf '  %-44s unknown\n' "$(model_set_title "$set")"
    fi
  done
  printf '  %-44s %s\n' Total "$(format_bytes "$total")"
  printf 'Profile: %s\n' "$(profile_installed && echo installed || echo not-installed)"
}

print_features() {
  local f
  for f in "${FEATURES[@]}"; do printf '%-28s %s\n' "$f" "$(feature_title "$f")"; done
}

open_profile_settings() {
  open 'x-apple.systempreferences:com.apple.Profiles-Settings.extension' 2>/dev/null || open 'x-apple.systempreferences:com.apple.preferences.configurationprofiles' 2>/dev/null || true
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
  printf 'Turn off Apple Intelligence and reset the selected models? [y/N] '
  read -r answer
  [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

off_command() {
  parse_args "$@"
  build_helper
  legacy_profile_installed && fail "legacy RemoveMacAI profile is installed; run '$0 revert' first"
  validate_uaf_catalog
  local sets
  sets="$(sets_to_remove)"

  printf 'Features to disable:\n'
  local f
  for f in "${FEATURES[@]}"; do kept "$f" || printf '  - %s\n' "$(feature_title "$f")"; done
  printf 'Model sets to reset:\n%s\n' "$(printf '%s\n' "$sets" | sed 's/^/  - /')"

  if (( DRY_RUN == 1 )); then
    local dry="${TMPDIR:-/tmp}/Apple-AI-remover.$$.mobileconfig"
    build_profile "$dry" "$sets"
    info 'DRY RUN: no profile was installed and no model was reset.'
    info "generated profile: $dry"
    return 0
  fi

  confirm || { info 'Nothing changed.'; return 0; }

  local expected
  expected="$(keep_csv)"
  build_profile "$PROFILE_FILE" "$sets"
  open "$PROFILE_FILE" 2>/dev/null || true
  open_profile_settings
  info "Approve '$PROFILE_NAME' in System Settings."
  wait_for_profile "$expected" || fail 'profile installation was not observed; no model reset was attempted'

  if [[ -n "$sets" ]]; then
    if reset_models "$sets"; then
      info 'All selected model sets reset successfully.'
    else
      fail 'profile is installed, but one or more model resets failed; run status to inspect remaining model state'
    fi
  fi
  info "Done. Run: $0 status"
}

revert_command() {
  build_helper
  local current=0 legacy=0
  profile_installed && current=1
  legacy_profile_installed && legacy=1
  if (( current == 0 && legacy == 0 )); then info 'No Apple AI remover profile is installed.'; return 0; fi
  if (( YES == 0 )); then
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
  local f set x saved_keep all a b
  for f in "${FEATURES[@]}"; do
    feature_title "$f" >/dev/null || fail "missing title for $f"
    while IFS= read -r x; do
      [[ -z "$x" ]] && continue
      model_set_asset_type "$x" >/dev/null || fail "unknown model set $x referenced by $f"
    done < <(feature_model_sets "$f")
  done
  for set in "${MODEL_SETS[@]}"; do model_set_asset_type "$set" >/dev/null || fail "missing model-set mapping $set"; done

  saved_keep=("${KEEP[@]}")
  KEEP=()
  all="$(sets_to_remove)"
  [[ "$(printf '%s\n' "$all" | sort)" == "$(printf '%s\n' "${MODEL_SETS[@]}" | sort)" ]] || fail 'empty keep set must remove every model set'

  KEEP=(writing-tools)
  all="$(sets_to_remove)"
  ! grep -qx 'com.apple.modelcatalog' <<< "$all" || fail 'writing-tools must protect foundation models'
  grep -qx 'com.apple.MobileAsset.UAF.FM.Visual' <<< "$all" || fail 'writing-tools unexpectedly protects visual models'
  KEEP=("${saved_keep[@]}")

  a="$(stable_uuid "$PROFILE_ID")"; b="$(stable_uuid "$PROFILE_ID")"; [[ "$a" == "$b" ]] || fail 'payload UUID generator is not stable'
  printf 'selftest: PASS (%s features, %s model sets)\n' "${#FEATURES[@]}" "${#MODEL_SETS[@]}"
}

usage() {
  cat <<EOF_USAGE
$PRODUCT_NAME $VERSION

Usage:
  $0 status
  $0 features
  $0 off [--keep feature[,feature...]] [--dry-run] [--yes]
  $0 revert [--yes]
  $0 selftest

The mutating commands target macOS $TARGET_MAJOR.x on Apple silicon.
EOF_USAGE
}

main() {
  local command="${1:-status}"
  shift || true
  case "$command" in
    status) require_platform; status_command "$@" ;;
    features) [[ "$#" -eq 0 ]] || fail 'features takes no options'; print_features ;;
    off) require_platform; off_command "$@" ;;
    revert) require_platform; parse_args "$@"; revert_command ;;
    selftest) [[ "$#" -eq 0 ]] || fail 'selftest takes no options'; selftest_command ;;
    --help|-h|help) usage ;;
    --version|-v|version) echo "$VERSION" ;;
    *) usage >&2; exit 1 ;;
  esac
}

main "$@"
\t'"${value}"
    [[ -n "$set" ]] || continue
    key="DownloadServerBaseURLOverride-$(model_set_asset_type "$set")"
    PREF_LINES="${PREF_LINES}com.apple.MobileAsset"$'\t'"${key}"$'\t'"${BLOCKED_URL}"$'\n'
  done <<< "$sets"

  mkdir -p "$(dirname "$output")"
  {
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
    printf '%s\n' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    printf '%s\n' '<plist version="1.0"><dict>'
    printf '%s\n' '<key>PayloadType</key><string>Configuration</string>'
    printf '%s\n' '<key>PayloadVersion</key><integer>1</integer>'
    printf '<key>PayloadIdentifier</key><string>%s</string>\n' "$PROFILE_ID"
    printf '<key>PayloadUUID</key><string>%s</string>\n' "$(stable_uuid "$PROFILE_ID")"
    printf '<key>PayloadDisplayName</key><string>%s</string>\n' "$(xml_escape "$PROFILE_NAME")"
    printf '%s\n' '<key>PayloadDescription</key><string>Disables Apple Intelligence features and prevents selected model sets from being re-downloaded. Remove this profile to undo.</string>'
    printf '%s\n' '<key>PayloadOrganization</key><string>Apple AI remover</string>'
    printf '%s\n' '<key>PayloadScope</key><string>System</string>'
    printf '%s\n' '<key>PayloadRemovalDisallowed</key><false/>'
    printf '%s\n' '<key>PayloadContent</key><array>'

    payload_header com.apple.applicationaccess restrictions 'Apple Intelligence restrictions'
    printf '%s\n' '      <key>PayloadContent</key><dict>'
    for feature in "${FEATURES[@]}"; do
      kept "$feature" && continue
      while IFS= read -r key; do
        [[ -n "$key" ]] && printf '        <key>%s</key><false/>\n' "$(xml_escape "$key")"
      done < <(feature_restrictions "$feature")
    done
    printf '%s\n' '      </dict>' '    </dict>'

    for d in com.apple.assistant.support com.apple.Siri group.com.apple.mail group.com.apple.usernoted com.apple.MobileSMS .GlobalPreferences com.apple.spatialphotosrelive; do
      PREF_LINES=''
      while IFS=$'\t' read -r domain key value; do
        [[ "$domain" == "$d" ]] || continue
        PREF_LINES="${PREF_LINES}${key}"$'\t'"${value}"$'\n'
      done <<< "$ALL_PREFS"
      append_pref_payload "$d" "$d" "Forced settings: $d"
    done

    PREF_LINES=''
    while IFS=$'\t' read -r domain key value; do
      [[ "$domain" == 'com.apple.MobileAsset' ]] || continue
      PREF_LINES="${PREF_LINES}${key}"$'\t'"${value}"$'\n'
    done <<< "$ALL_PREFS"
    append_pref_payload com.apple.MobileAsset MobileAsset 'MobileAsset download overrides'

    PREF_LINES="installed"$'\t'true$'\n'"kept"$'\t'"$(keep_csv)"$'\n'
    append_pref_payload "$PROFILE_ID" marker 'Apple AI remover state'

    printf '%s\n' '</array></dict></plist>'
  } > "$tmp"
  /usr/bin/plutil -lint "$tmp" >/dev/null 2>&1 || { rm -f "$tmp"; fail 'generated profile failed plist validation'; }
  mv "$tmp" "$output"
}

keep_csv() {
  local out='' item
  for item in "${KEEP[@]}"; do
    [[ -n "$out" ]] && out="$out,"
    out="$out$item"
  done
  printf '%s' "$out"
}

helper_pref() { "$HELPER" pref "$1" "$2"; }
profile_installed() { local o; o="$(helper_pref "$PROFILE_ID" installed 2>/dev/null)" || return 1; [[ "$o" == *$'forced=1\tvalue=true'* ]]; }
legacy_profile_installed() { local o; o="$(helper_pref "$LEGACY_PROFILE_ID" installed 2>/dev/null)" || return 1; [[ "$o" == *$'forced=1\tvalue=true'* ]]; }
profile_kept_csv() { local o; o="$(helper_pref "$PROFILE_ID" kept 2>/dev/null)" || return 1; printf '%s' "${o#*value=}"; }

validate_uaf_catalog() {
  local set expected actual
  for set in "${MODEL_SETS[@]}"; do
    expected="$(model_set_asset_type "$set")"
    actual="$($HELPER asset-type "$set")" || fail "UAF asset-set lookup failed for $set"
    [[ "$actual" == "$expected" ]] || fail "UAF mapping mismatch for $set: expected $expected, got $actual"
  done
}

model_bytes() {
  local set="$1" out
  out="$($HELPER bytes "$set" 2>/dev/null)" || return 1
  [[ "$out" =~ ^[0-9]+$ ]] || return 1
  printf '%s' "$out"
}

format_bytes() {
  local b="$1"
  if (( b >= 1000000000 )); then awk -v n="$b" 'BEGIN { printf "%.1f GB", n/1e9 }'
  elif (( b > 0 )); then awk -v n="$b" 'BEGIN { printf "%.0f MB", n/1e6 }'
  else echo '0 MB'; fi
}

feature_state() {
  local feature="$1" domain key want output forced value
  local all=1 any=0
  while IFS=$'\t' read -r domain key want; do
    [[ -n "$domain" ]] || continue
    output="$(helper_pref "$domain" "$key" 2>/dev/null)" || { echo unknown; return; }
    forced="$(printf '%s' "$output" | sed -n 's/.*forced=\([^\t]*\).*/\1/p')"
    value="$(printf '%s' "$output" | sed -n 's/.*value=\([^\t]*\)$/\1/p')"
    [[ "$forced" == 1 && "$value" == "$want" ]] && any=1 || all=0
  done < <(feature_preferences "$feature")
  if (( all == 1 && any == 1 )); then echo locked; return; fi

  case "$feature" in
    chatgpt|writing-tools|genmoji|image-playground|safari-summaries|notes-summaries)
      local restricted_ok=1 r
      while IFS= read -r r; do
        [[ -n "$r" ]] || continue
        output="$(helper_pref com.apple.applicationaccess "$r" 2>/dev/null)" || { echo unknown; return; }
        [[ "$output" == *$'forced=1\tvalue=false'* ]] || restricted_ok=0
      done < <(feature_restrictions "$feature")
      (( restricted_ok == 1 )) && echo locked && return
      ;;
  esac

  if profile_installed && ! kept "$feature" && [[ -z "$(feature_preferences "$feature")" ]] && [[ -z "$(feature_restrictions "$feature")" ]]; then
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
  local feature state set n total=0
  for feature in "${FEATURES[@]}"; do
    state="$(feature_state "$feature")"
    printf '%-44s %s\n' "$(feature_title "$feature")" "$state"
  done
  printf '\nModels on disk\n'
  for set in "${MODEL_SETS[@]}"; do
    if n="$(model_bytes "$set")"; then
      total=$((total+n)); printf '  %-44s %s\n' "$(model_set_title "$set")" "$(format_bytes "$n")"
    else
      printf '  %-44s unknown\n' "$(model_set_title "$set")"
    fi
  done
  printf '  %-44s %s\n' Total "$(format_bytes "$total")"
  printf 'Profile: %s\n' "$(profile_installed && echo installed || echo not-installed)"
}

print_features() {
  local f
  for f in "${FEATURES[@]}"; do printf '%-28s %s\n' "$f" "$(feature_title "$f")"; done
}

open_profile_settings() {
  open 'x-apple.systempreferences:com.apple.Profiles-Settings.extension' 2>/dev/null || open 'x-apple.systempreferences:com.apple.preferences.configurationprofiles' 2>/dev/null || true
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
  printf 'Turn off Apple Intelligence and reset the selected models? [y/N] '
  read -r answer
  [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

off_command() {
  parse_args "$@"
  build_helper
  legacy_profile_installed && fail "legacy RemoveMacAI profile is installed; run '$0 revert' first"
  validate_uaf_catalog
  local sets
  sets="$(sets_to_remove)"

  printf 'Features to disable:\n'
  local f
  for f in "${FEATURES[@]}"; do kept "$f" || printf '  - %s\n' "$(feature_title "$f")"; done
  printf 'Model sets to reset:\n%s\n' "$(printf '%s\n' "$sets" | sed 's/^/  - /')"

  if (( DRY_RUN == 1 )); then
    local dry="${TMPDIR:-/tmp}/Apple-AI-remover.$$.mobileconfig"
    build_profile "$dry" "$sets"
    info 'DRY RUN: no profile was installed and no model was reset.'
    info "generated profile: $dry"
    return 0
  fi

  confirm || { info 'Nothing changed.'; return 0; }

  local expected
  expected="$(keep_csv)"
  build_profile "$PROFILE_FILE" "$sets"
  open "$PROFILE_FILE" 2>/dev/null || true
  open_profile_settings
  info "Approve '$PROFILE_NAME' in System Settings."
  wait_for_profile "$expected" || fail 'profile installation was not observed; no model reset was attempted'

  if [[ -n "$sets" ]]; then
    if reset_models "$sets"; then
      info 'All selected model sets reset successfully.'
    else
      fail 'profile is installed, but one or more model resets failed; run status to inspect remaining model state'
    fi
  fi
  info "Done. Run: $0 status"
}

revert_command() {
  build_helper
  local current=0 legacy=0
  profile_installed && current=1
  legacy_profile_installed && legacy=1
  if (( current == 0 && legacy == 0 )); then info 'No Apple AI remover profile is installed.'; return 0; fi
  if (( YES == 0 )); then
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
  local f set x saved_keep all a b
  for f in "${FEATURES[@]}"; do
    feature_title "$f" >/dev/null || fail "missing title for $f"
    while IFS= read -r x; do
      [[ -z "$x" ]] && continue
      model_set_asset_type "$x" >/dev/null || fail "unknown model set $x referenced by $f"
    done < <(feature_model_sets "$f")
  done
  for set in "${MODEL_SETS[@]}"; do model_set_asset_type "$set" >/dev/null || fail "missing model-set mapping $set"; done

  saved_keep=("${KEEP[@]}")
  KEEP=()
  all="$(sets_to_remove)"
  [[ "$(printf '%s\n' "$all" | sort)" == "$(printf '%s\n' "${MODEL_SETS[@]}" | sort)" ]] || fail 'empty keep set must remove every model set'

  KEEP=(writing-tools)
  all="$(sets_to_remove)"
  ! grep -qx 'com.apple.modelcatalog' <<< "$all" || fail 'writing-tools must protect foundation models'
  grep -qx 'com.apple.MobileAsset.UAF.FM.Visual' <<< "$all" || fail 'writing-tools unexpectedly protects visual models'
  KEEP=("${saved_keep[@]}")

  a="$(stable_uuid "$PROFILE_ID")"; b="$(stable_uuid "$PROFILE_ID")"; [[ "$a" == "$b" ]] || fail 'payload UUID generator is not stable'
  printf 'selftest: PASS (%s features, %s model sets)\n' "${#FEATURES[@]}" "${#MODEL_SETS[@]}"
}

usage() {
  cat <<EOF_USAGE
$PRODUCT_NAME $VERSION

Usage:
  $0 status
  $0 features
  $0 off [--keep feature[,feature...]] [--dry-run] [--yes]
  $0 revert [--yes]
  $0 selftest

The mutating commands target macOS $TARGET_MAJOR.x on Apple silicon.
EOF_USAGE
}

main() {
  local command="${1:-status}"
  shift || true
  case "$command" in
    status) require_platform; status_command "$@" ;;
    features) [[ "$#" -eq 0 ]] || fail 'features takes no options'; print_features ;;
    off) require_platform; off_command "$@" ;;
    revert) require_platform; parse_args "$@"; revert_command ;;
    selftest) [[ "$#" -eq 0 ]] || fail 'selftest takes no options'; selftest_command ;;
    --help|-h|help) usage ;;
    --version|-v|version) echo "$VERSION" ;;
    *) usage >&2; exit 1 ;;
  esac
}

main "$@"
\n'
    done < <(feature_preferences "$feature")
  done
  while IFS= read -r set; do
    [[ -n "$set" ]] || continue
    key="DownloadServerBaseURLOverride-$(model_set_asset_type "$set")"
    PREF_LINES="${PREF_LINES}com.apple.MobileAsset"$'\t'"${key}"$'\t'"${BLOCKED_URL}"$'\n'
  done <<< "$sets"

  mkdir -p "$(dirname "$output")"
  {
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
    printf '%s\n' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    printf '%s\n' '<plist version="1.0"><dict>'
    printf '%s\n' '<key>PayloadType</key><string>Configuration</string>'
    printf '%s\n' '<key>PayloadVersion</key><integer>1</integer>'
    printf '<key>PayloadIdentifier</key><string>%s</string>\n' "$PROFILE_ID"
    printf '<key>PayloadUUID</key><string>%s</string>\n' "$(stable_uuid "$PROFILE_ID")"
    printf '<key>PayloadDisplayName</key><string>%s</string>\n' "$(xml_escape "$PROFILE_NAME")"
    printf '%s\n' '<key>PayloadDescription</key><string>Disables Apple Intelligence features and prevents selected model sets from being re-downloaded. Remove this profile to undo.</string>'
    printf '%s\n' '<key>PayloadOrganization</key><string>Apple AI remover</string>'
    printf '%s\n' '<key>PayloadScope</key><string>System</string>'
    printf '%s\n' '<key>PayloadRemovalDisallowed</key><false/>'
    printf '%s\n' '<key>PayloadContent</key><array>'

    payload_header com.apple.applicationaccess restrictions 'Apple Intelligence restrictions'
    printf '%s\n' '      <key>PayloadContent</key><dict>'
    for feature in "${FEATURES[@]}"; do
      kept "$feature" && continue
      while IFS= read -r key; do
        [[ -n "$key" ]] && printf '        <key>%s</key><false/>\n' "$(xml_escape "$key")"
      done < <(feature_restrictions "$feature")
    done
    printf '%s\n' '      </dict>' '    </dict>'

    for d in com.apple.assistant.support com.apple.Siri group.com.apple.mail group.com.apple.usernoted com.apple.MobileSMS .GlobalPreferences com.apple.spatialphotosrelive; do
      PREF_LINES=''
      while IFS=$'\t' read -r domain key value; do
        [[ "$domain" == "$d" ]] || continue
        PREF_LINES="${PREF_LINES}${key}"$'\t'"${value}"$'\n'
      done <<< "$ALL_PREFS"
      append_pref_payload "$d" "$d" "Forced settings: $d"
    done

    PREF_LINES=''
    while IFS=$'\t' read -r domain key value; do
      [[ "$domain" == 'com.apple.MobileAsset' ]] || continue
      PREF_LINES="${PREF_LINES}${key}"$'\t'"${value}"$'\n'
    done <<< "$ALL_PREFS"
    append_pref_payload com.apple.MobileAsset MobileAsset 'MobileAsset download overrides'

    PREF_LINES="installed"$'\t'true$'\n'"kept"$'\t'"$(keep_csv)"$'\n'
    append_pref_payload "$PROFILE_ID" marker 'Apple AI remover state'

    printf '%s\n' '</array></dict></plist>'
  } > "$tmp"
  /usr/bin/plutil -lint "$tmp" >/dev/null 2>&1 || { rm -f "$tmp"; fail 'generated profile failed plist validation'; }
  mv "$tmp" "$output"
}

keep_csv() {
  local out='' item
  for item in "${KEEP[@]}"; do
    [[ -n "$out" ]] && out="$out,"
    out="$out$item"
  done
  printf '%s' "$out"
}

helper_pref() { "$HELPER" pref "$1" "$2"; }
profile_installed() { local o; o="$(helper_pref "$PROFILE_ID" installed 2>/dev/null)" || return 1; [[ "$o" == *$'forced=1\tvalue=true'* ]]; }
legacy_profile_installed() { local o; o="$(helper_pref "$LEGACY_PROFILE_ID" installed 2>/dev/null)" || return 1; [[ "$o" == *$'forced=1\tvalue=true'* ]]; }
profile_kept_csv() { local o; o="$(helper_pref "$PROFILE_ID" kept 2>/dev/null)" || return 1; printf '%s' "${o#*value=}"; }

validate_uaf_catalog() {
  local set expected actual
  for set in "${MODEL_SETS[@]}"; do
    expected="$(model_set_asset_type "$set")"
    actual="$($HELPER asset-type "$set")" || fail "UAF asset-set lookup failed for $set"
    [[ "$actual" == "$expected" ]] || fail "UAF mapping mismatch for $set: expected $expected, got $actual"
  done
}

model_bytes() {
  local set="$1" out
  out="$($HELPER bytes "$set" 2>/dev/null)" || return 1
  [[ "$out" =~ ^[0-9]+$ ]] || return 1
  printf '%s' "$out"
}

format_bytes() {
  local b="$1"
  if (( b >= 1000000000 )); then awk -v n="$b" 'BEGIN { printf "%.1f GB", n/1e9 }'
  elif (( b > 0 )); then awk -v n="$b" 'BEGIN { printf "%.0f MB", n/1e6 }'
  else echo '0 MB'; fi
}

feature_state() {
  local feature="$1" domain key want output forced value
  local all=1 any=0
  while IFS=$'\t' read -r domain key want; do
    [[ -n "$domain" ]] || continue
    output="$(helper_pref "$domain" "$key" 2>/dev/null)" || { echo unknown; return; }
    forced="$(printf '%s' "$output" | sed -n 's/.*forced=\([^\t]*\).*/\1/p')"
    value="$(printf '%s' "$output" | sed -n 's/.*value=\([^\t]*\)$/\1/p')"
    [[ "$forced" == 1 && "$value" == "$want" ]] && any=1 || all=0
  done < <(feature_preferences "$feature")
  if (( all == 1 && any == 1 )); then echo locked; return; fi

  case "$feature" in
    chatgpt|writing-tools|genmoji|image-playground|safari-summaries|notes-summaries)
      local restricted_ok=1 r
      while IFS= read -r r; do
        [[ -n "$r" ]] || continue
        output="$(helper_pref com.apple.applicationaccess "$r" 2>/dev/null)" || { echo unknown; return; }
        [[ "$output" == *$'forced=1\tvalue=false'* ]] || restricted_ok=0
      done < <(feature_restrictions "$feature")
      (( restricted_ok == 1 )) && echo locked && return
      ;;
  esac

  if profile_installed && ! kept "$feature" && [[ -z "$(feature_preferences "$feature")" ]] && [[ -z "$(feature_restrictions "$feature")" ]]; then
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
  local feature state set n total=0
  for feature in "${FEATURES[@]}"; do
    state="$(feature_state "$feature")"
    printf '%-44s %s\n' "$(feature_title "$feature")" "$state"
  done
  printf '\nModels on disk\n'
  for set in "${MODEL_SETS[@]}"; do
    if n="$(model_bytes "$set")"; then
      total=$((total+n)); printf '  %-44s %s\n' "$(model_set_title "$set")" "$(format_bytes "$n")"
    else
      printf '  %-44s unknown\n' "$(model_set_title "$set")"
    fi
  done
  printf '  %-44s %s\n' Total "$(format_bytes "$total")"
  printf 'Profile: %s\n' "$(profile_installed && echo installed || echo not-installed)"
}

print_features() {
  local f
  for f in "${FEATURES[@]}"; do printf '%-28s %s\n' "$f" "$(feature_title "$f")"; done
}

open_profile_settings() {
  open 'x-apple.systempreferences:com.apple.Profiles-Settings.extension' 2>/dev/null || open 'x-apple.systempreferences:com.apple.preferences.configurationprofiles' 2>/dev/null || true
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
  printf 'Turn off Apple Intelligence and reset the selected models? [y/N] '
  read -r answer
  [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

off_command() {
  parse_args "$@"
  build_helper
  legacy_profile_installed && fail "legacy RemoveMacAI profile is installed; run '$0 revert' first"
  validate_uaf_catalog
  local sets
  sets="$(sets_to_remove)"

  printf 'Features to disable:\n'
  local f
  for f in "${FEATURES[@]}"; do kept "$f" || printf '  - %s\n' "$(feature_title "$f")"; done
  printf 'Model sets to reset:\n%s\n' "$(printf '%s\n' "$sets" | sed 's/^/  - /')"

  if (( DRY_RUN == 1 )); then
    local dry="${TMPDIR:-/tmp}/Apple-AI-remover.$$.mobileconfig"
    build_profile "$dry" "$sets"
    info 'DRY RUN: no profile was installed and no model was reset.'
    info "generated profile: $dry"
    return 0
  fi

  confirm || { info 'Nothing changed.'; return 0; }

  local expected
  expected="$(keep_csv)"
  build_profile "$PROFILE_FILE" "$sets"
  open "$PROFILE_FILE" 2>/dev/null || true
  open_profile_settings
  info "Approve '$PROFILE_NAME' in System Settings."
  wait_for_profile "$expected" || fail 'profile installation was not observed; no model reset was attempted'

  if [[ -n "$sets" ]]; then
    if reset_models "$sets"; then
      info 'All selected model sets reset successfully.'
    else
      fail 'profile is installed, but one or more model resets failed; run status to inspect remaining model state'
    fi
  fi
  info "Done. Run: $0 status"
}

revert_command() {
  build_helper
  local current=0 legacy=0
  profile_installed && current=1
  legacy_profile_installed && legacy=1
  if (( current == 0 && legacy == 0 )); then info 'No Apple AI remover profile is installed.'; return 0; fi
  if (( YES == 0 )); then
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
  local f set x saved_keep all a b
  for f in "${FEATURES[@]}"; do
    feature_title "$f" >/dev/null || fail "missing title for $f"
    while IFS= read -r x; do
      [[ -z "$x" ]] && continue
      model_set_asset_type "$x" >/dev/null || fail "unknown model set $x referenced by $f"
    done < <(feature_model_sets "$f")
  done
  for set in "${MODEL_SETS[@]}"; do model_set_asset_type "$set" >/dev/null || fail "missing model-set mapping $set"; done

  saved_keep=("${KEEP[@]}")
  KEEP=()
  all="$(sets_to_remove)"
  [[ "$(printf '%s\n' "$all" | sort)" == "$(printf '%s\n' "${MODEL_SETS[@]}" | sort)" ]] || fail 'empty keep set must remove every model set'

  KEEP=(writing-tools)
  all="$(sets_to_remove)"
  ! grep -qx 'com.apple.modelcatalog' <<< "$all" || fail 'writing-tools must protect foundation models'
  grep -qx 'com.apple.MobileAsset.UAF.FM.Visual' <<< "$all" || fail 'writing-tools unexpectedly protects visual models'
  KEEP=("${saved_keep[@]}")

  a="$(stable_uuid "$PROFILE_ID")"; b="$(stable_uuid "$PROFILE_ID")"; [[ "$a" == "$b" ]] || fail 'payload UUID generator is not stable'
  printf 'selftest: PASS (%s features, %s model sets)\n' "${#FEATURES[@]}" "${#MODEL_SETS[@]}"
}

usage() {
  cat <<EOF_USAGE
$PRODUCT_NAME $VERSION

Usage:
  $0 status
  $0 features
  $0 off [--keep feature[,feature...]] [--dry-run] [--yes]
  $0 revert [--yes]
  $0 selftest

The mutating commands target macOS $TARGET_MAJOR.x on Apple silicon.
EOF_USAGE
}

main() {
  local command="${1:-status}"
  shift || true
  case "$command" in
    status) require_platform; status_command "$@" ;;
    features) [[ "$#" -eq 0 ]] || fail 'features takes no options'; print_features ;;
    off) require_platform; off_command "$@" ;;
    revert) require_platform; parse_args "$@"; revert_command ;;
    selftest) [[ "$#" -eq 0 ]] || fail 'selftest takes no options'; selftest_command ;;
    --help|-h|help) usage ;;
    --version|-v|version) echo "$VERSION" ;;
    *) usage >&2; exit 1 ;;
  esac
}

main "$@"
forced=1\tvalue=true'* ]]; }
profile_kept_csv() { local o; o="$(helper_pref "$PROFILE_ID" kept 2>/dev/null)" || return 1; printf '%s' "\${o#*value=}"; }

validate_uaf_catalog() {
  local set expected actual
  for set in "${MODEL_SETS[@]}"; do
    expected="$(model_set_asset_type "$set")"
    actual="$($HELPER asset-type "$set")" || fail "UAF asset-set lookup failed for $set"
    [[ "$actual" == "$expected" ]] || fail "UAF mapping mismatch for $set: expected $expected, got $actual"
  done
}

model_bytes() {
  local set="$1" out
  out="$($HELPER bytes "$set" 2>/dev/null)" || return 1
  [[ "$out" =~ ^[0-9]+$ ]] || return 1
  printf '%s' "$out"
}

format_bytes() {
  local b="$1"
  if (( b >= 1000000000 )); then awk -v n="$b" 'BEGIN { printf "%.1f GB", n/1e9 }'
  elif (( b > 0 )); then awk -v n="$b" 'BEGIN { printf "%.0f MB", n/1e6 }'
  else echo '0 MB'; fi
}

feature_state() {
  local feature="$1" domain key want output forced value
  local all=1 any=0
  while IFS=$'\t' read -r domain key want; do
    [[ -n "$domain" ]] || continue
    output="$(helper_pref "$domain" "$key" 2>/dev/null)" || { echo unknown; return; }
    forced="$(printf '%s' "$output" | sed -n 's/.*forced=\([^\t]*\).*/\1/p')"
    value="$(printf '%s' "$output" | sed -n 's/.*value=\([^\t]*\)$/\1/p')"
    [[ "$forced" == 1 && "$value" == "$want" ]] && any=1 || all=0
  done < <(feature_preferences "$feature")
  if (( all == 1 && any == 1 )); then echo locked; return; fi

  case "$feature" in
    chatgpt|writing-tools|genmoji|image-playground|safari-summaries|notes-summaries)
      local restricted_ok=1 r
      while IFS= read -r r; do
        [[ -n "$r" ]] || continue
        output="$(helper_pref com.apple.applicationaccess "$r" 2>/dev/null)" || { echo unknown; return; }
        [[ "$output" == *$'forced=1\tvalue=false'* ]] || restricted_ok=0
      done < <(feature_restrictions "$feature")
      (( restricted_ok == 1 )) && echo locked && return
      ;;
  esac

  if profile_installed && ! kept "$feature" && [[ -z "$(feature_preferences "$feature")" ]] && [[ -z "$(feature_restrictions "$feature")" ]]; then
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
  local feature state set n total=0
  for feature in "${FEATURES[@]}"; do
    state="$(feature_state "$feature")"
    printf '%-44s %s\n' "$(feature_title "$feature")" "$state"
  done
  printf '\nModels on disk\n'
  for set in "${MODEL_SETS[@]}"; do
    if n="$(model_bytes "$set")"; then
      total=$((total+n)); printf '  %-44s %s\n' "$(model_set_title "$set")" "$(format_bytes "$n")"
    else
      printf '  %-44s unknown\n' "$(model_set_title "$set")"
    fi
  done
  printf '  %-44s %s\n' Total "$(format_bytes "$total")"
  printf 'Profile: %s\n' "$(profile_installed && echo installed || echo not-installed)"
}

print_features() {
  local f
  for f in "${FEATURES[@]}"; do printf '%-28s %s\n' "$f" "$(feature_title "$f")"; done
}

open_profile_settings() {
  open 'x-apple.systempreferences:com.apple.Profiles-Settings.extension' 2>/dev/null || open 'x-apple.systempreferences:com.apple.preferences.configurationprofiles' 2>/dev/null || true
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
  printf 'Turn off Apple Intelligence and reset the selected models? [y/N] '
  read -r answer
  [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

off_command() {
  parse_args "$@"
  build_helper
  legacy_profile_installed && fail "legacy RemoveMacAI profile is installed; run '$0 revert' first"
  validate_uaf_catalog
  local sets
  sets="$(sets_to_remove)"

  printf 'Features to disable:\n'
  local f
  for f in "${FEATURES[@]}"; do kept "$f" || printf '  - %s\n' "$(feature_title "$f")"; done
  printf 'Model sets to reset:\n%s\n' "$(printf '%s\n' "$sets" | sed 's/^/  - /')"

  if (( DRY_RUN == 1 )); then
    local dry="${TMPDIR:-/tmp}/Apple-AI-remover.$$.mobileconfig"
    build_profile "$dry" "$sets"
    info 'DRY RUN: no profile was installed and no model was reset.'
    info "generated profile: $dry"
    return 0
  fi

  confirm || { info 'Nothing changed.'; return 0; }

  local expected
  expected="$(keep_csv)"
  build_profile "$PROFILE_FILE" "$sets"
  open "$PROFILE_FILE" 2>/dev/null || true
  open_profile_settings
  info "Approve '$PROFILE_NAME' in System Settings."
  wait_for_profile "$expected" || fail 'profile installation was not observed; no model reset was attempted'

  if [[ -n "$sets" ]]; then
    if reset_models "$sets"; then
      info 'All selected model sets reset successfully.'
    else
      fail 'profile is installed, but one or more model resets failed; run status to inspect remaining model state'
    fi
  fi
  info "Done. Run: $0 status"
}

revert_command() {
  build_helper
  local current=0 legacy=0
  profile_installed && current=1
  legacy_profile_installed && legacy=1
  if (( current == 0 && legacy == 0 )); then info 'No Apple AI remover profile is installed.'; return 0; fi
  if (( YES == 0 )); then
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
  local f set x saved_keep all a b
  for f in "${FEATURES[@]}"; do
    feature_title "$f" >/dev/null || fail "missing title for $f"
    while IFS= read -r x; do
      [[ -z "$x" ]] && continue
      model_set_asset_type "$x" >/dev/null || fail "unknown model set $x referenced by $f"
    done < <(feature_model_sets "$f")
  done
  for set in "${MODEL_SETS[@]}"; do model_set_asset_type "$set" >/dev/null || fail "missing model-set mapping $set"; done

  saved_keep=("${KEEP[@]}")
  KEEP=()
  all="$(sets_to_remove)"
  [[ "$(printf '%s\n' "$all" | sort)" == "$(printf '%s\n' "${MODEL_SETS[@]}" | sort)" ]] || fail 'empty keep set must remove every model set'

  KEEP=(writing-tools)
  all="$(sets_to_remove)"
  ! grep -qx 'com.apple.modelcatalog' <<< "$all" || fail 'writing-tools must protect foundation models'
  grep -qx 'com.apple.MobileAsset.UAF.FM.Visual' <<< "$all" || fail 'writing-tools unexpectedly protects visual models'
  KEEP=("${saved_keep[@]}")

  a="$(stable_uuid "$PROFILE_ID")"; b="$(stable_uuid "$PROFILE_ID")"; [[ "$a" == "$b" ]] || fail 'payload UUID generator is not stable'
  printf 'selftest: PASS (%s features, %s model sets)\n' "${#FEATURES[@]}" "${#MODEL_SETS[@]}"
}

usage() {
  cat <<EOF_USAGE
$PRODUCT_NAME $VERSION

Usage:
  $0 status
  $0 features
  $0 off [--keep feature[,feature...]] [--dry-run] [--yes]
  $0 revert [--yes]
  $0 selftest

The mutating commands target macOS $TARGET_MAJOR.x on Apple silicon.
EOF_USAGE
}

main() {
  local command="${1:-status}"
  shift || true
  case "$command" in
    status) require_platform; status_command "$@" ;;
    features) [[ "$#" -eq 0 ]] || fail 'features takes no options'; print_features ;;
    off) require_platform; off_command "$@" ;;
    revert) require_platform; parse_args "$@"; revert_command ;;
    selftest) [[ "$#" -eq 0 ]] || fail 'selftest takes no options'; selftest_command ;;
    --help|-h|help) usage ;;
    --version|-v|version) echo "$VERSION" ;;
    *) usage >&2; exit 1 ;;
  esac
}

main "$@"
\t'"${value}"
    [[ -n "$set" ]] || continue
    key="DownloadServerBaseURLOverride-$(model_set_asset_type "$set")"
    PREF_LINES="${PREF_LINES}com.apple.MobileAsset"$'\t'"${key}"$'\t'"${BLOCKED_URL}"$'\n'
  done <<< "$sets"

  mkdir -p "$(dirname "$output")"
  {
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
    printf '%s\n' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    printf '%s\n' '<plist version="1.0"><dict>'
    printf '%s\n' '<key>PayloadType</key><string>Configuration</string>'
    printf '%s\n' '<key>PayloadVersion</key><integer>1</integer>'
    printf '<key>PayloadIdentifier</key><string>%s</string>\n' "$PROFILE_ID"
    printf '<key>PayloadUUID</key><string>%s</string>\n' "$(stable_uuid "$PROFILE_ID")"
    printf '<key>PayloadDisplayName</key><string>%s</string>\n' "$(xml_escape "$PROFILE_NAME")"
    printf '%s\n' '<key>PayloadDescription</key><string>Disables Apple Intelligence features and prevents selected model sets from being re-downloaded. Remove this profile to undo.</string>'
    printf '%s\n' '<key>PayloadOrganization</key><string>Apple AI remover</string>'
    printf '%s\n' '<key>PayloadScope</key><string>System</string>'
    printf '%s\n' '<key>PayloadRemovalDisallowed</key><false/>'
    printf '%s\n' '<key>PayloadContent</key><array>'

    payload_header com.apple.applicationaccess restrictions 'Apple Intelligence restrictions'
    printf '%s\n' '      <key>PayloadContent</key><dict>'
    for feature in "${FEATURES[@]}"; do
      kept "$feature" && continue
      while IFS= read -r key; do
        [[ -n "$key" ]] && printf '        <key>%s</key><false/>\n' "$(xml_escape "$key")"
      done < <(feature_restrictions "$feature")
    done
    printf '%s\n' '      </dict>' '    </dict>'

    for d in com.apple.assistant.support com.apple.Siri group.com.apple.mail group.com.apple.usernoted com.apple.MobileSMS .GlobalPreferences com.apple.spatialphotosrelive; do
      PREF_LINES=''
      while IFS=$'\t' read -r domain key value; do
        [[ "$domain" == "$d" ]] || continue
        PREF_LINES="${PREF_LINES}${key}"$'\t'"${value}"$'\n'
      done <<< "$ALL_PREFS"
      append_pref_payload "$d" "$d" "Forced settings: $d"
    done

    PREF_LINES=''
    while IFS=$'\t' read -r domain key value; do
      [[ "$domain" == 'com.apple.MobileAsset' ]] || continue
      PREF_LINES="${PREF_LINES}${key}"$'\t'"${value}"$'\n'
    done <<< "$ALL_PREFS"
    append_pref_payload com.apple.MobileAsset MobileAsset 'MobileAsset download overrides'

    PREF_LINES="installed"$'\t'true$'\n'"kept"$'\t'"$(keep_csv)"$'\n'
    append_pref_payload "$PROFILE_ID" marker 'Apple AI remover state'

    printf '%s\n' '</array></dict></plist>'
  } > "$tmp"
  /usr/bin/plutil -lint "$tmp" >/dev/null 2>&1 || { rm -f "$tmp"; fail 'generated profile failed plist validation'; }
  mv "$tmp" "$output"
}

keep_csv() {
  local out='' item
  for item in "${KEEP[@]}"; do
    [[ -n "$out" ]] && out="$out,"
    out="$out$item"
  done
  printf '%s' "$out"
}

helper_pref() { "$HELPER" pref "$1" "$2"; }
profile_installed() { local o; o="$(helper_pref "$PROFILE_ID" installed 2>/dev/null)" || return 1; [[ "$o" == *$'forced=1\tvalue=true'* ]]; }
legacy_profile_installed() { local o; o="$(helper_pref "$LEGACY_PROFILE_ID" installed 2>/dev/null)" || return 1; [[ "$o" == *$'forced=1\tvalue=true'* ]]; }
profile_kept_csv() { local o; o="$(helper_pref "$PROFILE_ID" kept 2>/dev/null)" || return 1; printf '%s' "${o#*value=}"; }

validate_uaf_catalog() {
  local set expected actual
  for set in "${MODEL_SETS[@]}"; do
    expected="$(model_set_asset_type "$set")"
    actual="$($HELPER asset-type "$set")" || fail "UAF asset-set lookup failed for $set"
    [[ "$actual" == "$expected" ]] || fail "UAF mapping mismatch for $set: expected $expected, got $actual"
  done
}

model_bytes() {
  local set="$1" out
  out="$($HELPER bytes "$set" 2>/dev/null)" || return 1
  [[ "$out" =~ ^[0-9]+$ ]] || return 1
  printf '%s' "$out"
}

format_bytes() {
  local b="$1"
  if (( b >= 1000000000 )); then awk -v n="$b" 'BEGIN { printf "%.1f GB", n/1e9 }'
  elif (( b > 0 )); then awk -v n="$b" 'BEGIN { printf "%.0f MB", n/1e6 }'
  else echo '0 MB'; fi
}

feature_state() {
  local feature="$1" domain key want output forced value
  local all=1 any=0
  while IFS=$'\t' read -r domain key want; do
    [[ -n "$domain" ]] || continue
    output="$(helper_pref "$domain" "$key" 2>/dev/null)" || { echo unknown; return; }
    forced="$(printf '%s' "$output" | sed -n 's/.*forced=\([^\t]*\).*/\1/p')"
    value="$(printf '%s' "$output" | sed -n 's/.*value=\([^\t]*\)$/\1/p')"
    [[ "$forced" == 1 && "$value" == "$want" ]] && any=1 || all=0
  done < <(feature_preferences "$feature")
  if (( all == 1 && any == 1 )); then echo locked; return; fi

  case "$feature" in
    chatgpt|writing-tools|genmoji|image-playground|safari-summaries|notes-summaries)
      local restricted_ok=1 r
      while IFS= read -r r; do
        [[ -n "$r" ]] || continue
        output="$(helper_pref com.apple.applicationaccess "$r" 2>/dev/null)" || { echo unknown; return; }
        [[ "$output" == *$'forced=1\tvalue=false'* ]] || restricted_ok=0
      done < <(feature_restrictions "$feature")
      (( restricted_ok == 1 )) && echo locked && return
      ;;
  esac

  if profile_installed && ! kept "$feature" && [[ -z "$(feature_preferences "$feature")" ]] && [[ -z "$(feature_restrictions "$feature")" ]]; then
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
  local feature state set n total=0
  for feature in "${FEATURES[@]}"; do
    state="$(feature_state "$feature")"
    printf '%-44s %s\n' "$(feature_title "$feature")" "$state"
  done
  printf '\nModels on disk\n'
  for set in "${MODEL_SETS[@]}"; do
    if n="$(model_bytes "$set")"; then
      total=$((total+n)); printf '  %-44s %s\n' "$(model_set_title "$set")" "$(format_bytes "$n")"
    else
      printf '  %-44s unknown\n' "$(model_set_title "$set")"
    fi
  done
  printf '  %-44s %s\n' Total "$(format_bytes "$total")"
  printf 'Profile: %s\n' "$(profile_installed && echo installed || echo not-installed)"
}

print_features() {
  local f
  for f in "${FEATURES[@]}"; do printf '%-28s %s\n' "$f" "$(feature_title "$f")"; done
}

open_profile_settings() {
  open 'x-apple.systempreferences:com.apple.Profiles-Settings.extension' 2>/dev/null || open 'x-apple.systempreferences:com.apple.preferences.configurationprofiles' 2>/dev/null || true
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
  printf 'Turn off Apple Intelligence and reset the selected models? [y/N] '
  read -r answer
  [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

off_command() {
  parse_args "$@"
  build_helper
  legacy_profile_installed && fail "legacy RemoveMacAI profile is installed; run '$0 revert' first"
  validate_uaf_catalog
  local sets
  sets="$(sets_to_remove)"

  printf 'Features to disable:\n'
  local f
  for f in "${FEATURES[@]}"; do kept "$f" || printf '  - %s\n' "$(feature_title "$f")"; done
  printf 'Model sets to reset:\n%s\n' "$(printf '%s\n' "$sets" | sed 's/^/  - /')"

  if (( DRY_RUN == 1 )); then
    local dry="${TMPDIR:-/tmp}/Apple-AI-remover.$$.mobileconfig"
    build_profile "$dry" "$sets"
    info 'DRY RUN: no profile was installed and no model was reset.'
    info "generated profile: $dry"
    return 0
  fi

  confirm || { info 'Nothing changed.'; return 0; }

  local expected
  expected="$(keep_csv)"
  build_profile "$PROFILE_FILE" "$sets"
  open "$PROFILE_FILE" 2>/dev/null || true
  open_profile_settings
  info "Approve '$PROFILE_NAME' in System Settings."
  wait_for_profile "$expected" || fail 'profile installation was not observed; no model reset was attempted'

  if [[ -n "$sets" ]]; then
    if reset_models "$sets"; then
      info 'All selected model sets reset successfully.'
    else
      fail 'profile is installed, but one or more model resets failed; run status to inspect remaining model state'
    fi
  fi
  info "Done. Run: $0 status"
}

revert_command() {
  build_helper
  local current=0 legacy=0
  profile_installed && current=1
  legacy_profile_installed && legacy=1
  if (( current == 0 && legacy == 0 )); then info 'No Apple AI remover profile is installed.'; return 0; fi
  if (( YES == 0 )); then
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
  local f set x saved_keep all a b
  for f in "${FEATURES[@]}"; do
    feature_title "$f" >/dev/null || fail "missing title for $f"
    while IFS= read -r x; do
      [[ -z "$x" ]] && continue
      model_set_asset_type "$x" >/dev/null || fail "unknown model set $x referenced by $f"
    done < <(feature_model_sets "$f")
  done
  for set in "${MODEL_SETS[@]}"; do model_set_asset_type "$set" >/dev/null || fail "missing model-set mapping $set"; done

  saved_keep=("${KEEP[@]}")
  KEEP=()
  all="$(sets_to_remove)"
  [[ "$(printf '%s\n' "$all" | sort)" == "$(printf '%s\n' "${MODEL_SETS[@]}" | sort)" ]] || fail 'empty keep set must remove every model set'

  KEEP=(writing-tools)
  all="$(sets_to_remove)"
  ! grep -qx 'com.apple.modelcatalog' <<< "$all" || fail 'writing-tools must protect foundation models'
  grep -qx 'com.apple.MobileAsset.UAF.FM.Visual' <<< "$all" || fail 'writing-tools unexpectedly protects visual models'
  KEEP=("${saved_keep[@]}")

  a="$(stable_uuid "$PROFILE_ID")"; b="$(stable_uuid "$PROFILE_ID")"; [[ "$a" == "$b" ]] || fail 'payload UUID generator is not stable'
  printf 'selftest: PASS (%s features, %s model sets)\n' "${#FEATURES[@]}" "${#MODEL_SETS[@]}"
}

usage() {
  cat <<EOF_USAGE
$PRODUCT_NAME $VERSION

Usage:
  $0 status
  $0 features
  $0 off [--keep feature[,feature...]] [--dry-run] [--yes]
  $0 revert [--yes]
  $0 selftest

The mutating commands target macOS $TARGET_MAJOR.x on Apple silicon.
EOF_USAGE
}

main() {
  local command="${1:-status}"
  shift || true
  case "$command" in
    status) require_platform; status_command "$@" ;;
    features) [[ "$#" -eq 0 ]] || fail 'features takes no options'; print_features ;;
    off) require_platform; off_command "$@" ;;
    revert) require_platform; parse_args "$@"; revert_command ;;
    selftest) [[ "$#" -eq 0 ]] || fail 'selftest takes no options'; selftest_command ;;
    --help|-h|help) usage ;;
    --version|-v|version) echo "$VERSION" ;;
    *) usage >&2; exit 1 ;;
  esac
}

main "$@"
\n'
    done < <(feature_preferences "$feature")
  done
  while IFS= read -r set; do
    [[ -n "$set" ]] || continue
    key="DownloadServerBaseURLOverride-$(model_set_asset_type "$set")"
    PREF_LINES="${PREF_LINES}com.apple.MobileAsset"$'\t'"${key}"$'\t'"${BLOCKED_URL}"$'\n'
  done <<< "$sets"

  mkdir -p "$(dirname "$output")"
  {
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
    printf '%s\n' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    printf '%s\n' '<plist version="1.0"><dict>'
    printf '%s\n' '<key>PayloadType</key><string>Configuration</string>'
    printf '%s\n' '<key>PayloadVersion</key><integer>1</integer>'
    printf '<key>PayloadIdentifier</key><string>%s</string>\n' "$PROFILE_ID"
    printf '<key>PayloadUUID</key><string>%s</string>\n' "$(stable_uuid "$PROFILE_ID")"
    printf '<key>PayloadDisplayName</key><string>%s</string>\n' "$(xml_escape "$PROFILE_NAME")"
    printf '%s\n' '<key>PayloadDescription</key><string>Disables Apple Intelligence features and prevents selected model sets from being re-downloaded. Remove this profile to undo.</string>'
    printf '%s\n' '<key>PayloadOrganization</key><string>Apple AI remover</string>'
    printf '%s\n' '<key>PayloadScope</key><string>System</string>'
    printf '%s\n' '<key>PayloadRemovalDisallowed</key><false/>'
    printf '%s\n' '<key>PayloadContent</key><array>'

    payload_header com.apple.applicationaccess restrictions 'Apple Intelligence restrictions'
    printf '%s\n' '      <key>PayloadContent</key><dict>'
    for feature in "${FEATURES[@]}"; do
      kept "$feature" && continue
      while IFS= read -r key; do
        [[ -n "$key" ]] && printf '        <key>%s</key><false/>\n' "$(xml_escape "$key")"
      done < <(feature_restrictions "$feature")
    done
    printf '%s\n' '      </dict>' '    </dict>'

    for d in com.apple.assistant.support com.apple.Siri group.com.apple.mail group.com.apple.usernoted com.apple.MobileSMS .GlobalPreferences com.apple.spatialphotosrelive; do
      PREF_LINES=''
      while IFS=$'\t' read -r domain key value; do
        [[ "$domain" == "$d" ]] || continue
        PREF_LINES="${PREF_LINES}${key}"$'\t'"${value}"$'\n'
      done <<< "$ALL_PREFS"
      append_pref_payload "$d" "$d" "Forced settings: $d"
    done

    PREF_LINES=''
    while IFS=$'\t' read -r domain key value; do
      [[ "$domain" == 'com.apple.MobileAsset' ]] || continue
      PREF_LINES="${PREF_LINES}${key}"$'\t'"${value}"$'\n'
    done <<< "$ALL_PREFS"
    append_pref_payload com.apple.MobileAsset MobileAsset 'MobileAsset download overrides'

    PREF_LINES="installed"$'\t'true$'\n'"kept"$'\t'"$(keep_csv)"$'\n'
    append_pref_payload "$PROFILE_ID" marker 'Apple AI remover state'

    printf '%s\n' '</array></dict></plist>'
  } > "$tmp"
  /usr/bin/plutil -lint "$tmp" >/dev/null 2>&1 || { rm -f "$tmp"; fail 'generated profile failed plist validation'; }
  mv "$tmp" "$output"
}

keep_csv() {
  local out='' item
  for item in "${KEEP[@]}"; do
    [[ -n "$out" ]] && out="$out,"
    out="$out$item"
  done
  printf '%s' "$out"
}

helper_pref() { "$HELPER" pref "$1" "$2"; }
profile_installed() { local o; o="$(helper_pref "$PROFILE_ID" installed 2>/dev/null)" || return 1; [[ "$o" == *$'forced=1\tvalue=true'* ]]; }
legacy_profile_installed() { local o; o="$(helper_pref "$LEGACY_PROFILE_ID" installed 2>/dev/null)" || return 1; [[ "$o" == *$'forced=1\tvalue=true'* ]]; }
profile_kept_csv() { local o; o="$(helper_pref "$PROFILE_ID" kept 2>/dev/null)" || return 1; printf '%s' "${o#*value=}"; }

validate_uaf_catalog() {
  local set expected actual
  for set in "${MODEL_SETS[@]}"; do
    expected="$(model_set_asset_type "$set")"
    actual="$($HELPER asset-type "$set")" || fail "UAF asset-set lookup failed for $set"
    [[ "$actual" == "$expected" ]] || fail "UAF mapping mismatch for $set: expected $expected, got $actual"
  done
}

model_bytes() {
  local set="$1" out
  out="$($HELPER bytes "$set" 2>/dev/null)" || return 1
  [[ "$out" =~ ^[0-9]+$ ]] || return 1
  printf '%s' "$out"
}

format_bytes() {
  local b="$1"
  if (( b >= 1000000000 )); then awk -v n="$b" 'BEGIN { printf "%.1f GB", n/1e9 }'
  elif (( b > 0 )); then awk -v n="$b" 'BEGIN { printf "%.0f MB", n/1e6 }'
  else echo '0 MB'; fi
}

feature_state() {
  local feature="$1" domain key want output forced value
  local all=1 any=0
  while IFS=$'\t' read -r domain key want; do
    [[ -n "$domain" ]] || continue
    output="$(helper_pref "$domain" "$key" 2>/dev/null)" || { echo unknown; return; }
    forced="$(printf '%s' "$output" | sed -n 's/.*forced=\([^\t]*\).*/\1/p')"
    value="$(printf '%s' "$output" | sed -n 's/.*value=\([^\t]*\)$/\1/p')"
    [[ "$forced" == 1 && "$value" == "$want" ]] && any=1 || all=0
  done < <(feature_preferences "$feature")
  if (( all == 1 && any == 1 )); then echo locked; return; fi

  case "$feature" in
    chatgpt|writing-tools|genmoji|image-playground|safari-summaries|notes-summaries)
      local restricted_ok=1 r
      while IFS= read -r r; do
        [[ -n "$r" ]] || continue
        output="$(helper_pref com.apple.applicationaccess "$r" 2>/dev/null)" || { echo unknown; return; }
        [[ "$output" == *$'forced=1\tvalue=false'* ]] || restricted_ok=0
      done < <(feature_restrictions "$feature")
      (( restricted_ok == 1 )) && echo locked && return
      ;;
  esac

  if profile_installed && ! kept "$feature" && [[ -z "$(feature_preferences "$feature")" ]] && [[ -z "$(feature_restrictions "$feature")" ]]; then
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
  local feature state set n total=0
  for feature in "${FEATURES[@]}"; do
    state="$(feature_state "$feature")"
    printf '%-44s %s\n' "$(feature_title "$feature")" "$state"
  done
  printf '\nModels on disk\n'
  for set in "${MODEL_SETS[@]}"; do
    if n="$(model_bytes "$set")"; then
      total=$((total+n)); printf '  %-44s %s\n' "$(model_set_title "$set")" "$(format_bytes "$n")"
    else
      printf '  %-44s unknown\n' "$(model_set_title "$set")"
    fi
  done
  printf '  %-44s %s\n' Total "$(format_bytes "$total")"
  printf 'Profile: %s\n' "$(profile_installed && echo installed || echo not-installed)"
}

print_features() {
  local f
  for f in "${FEATURES[@]}"; do printf '%-28s %s\n' "$f" "$(feature_title "$f")"; done
}

open_profile_settings() {
  open 'x-apple.systempreferences:com.apple.Profiles-Settings.extension' 2>/dev/null || open 'x-apple.systempreferences:com.apple.preferences.configurationprofiles' 2>/dev/null || true
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
  printf 'Turn off Apple Intelligence and reset the selected models? [y/N] '
  read -r answer
  [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

off_command() {
  parse_args "$@"
  build_helper
  legacy_profile_installed && fail "legacy RemoveMacAI profile is installed; run '$0 revert' first"
  validate_uaf_catalog
  local sets
  sets="$(sets_to_remove)"

  printf 'Features to disable:\n'
  local f
  for f in "${FEATURES[@]}"; do kept "$f" || printf '  - %s\n' "$(feature_title "$f")"; done
  printf 'Model sets to reset:\n%s\n' "$(printf '%s\n' "$sets" | sed 's/^/  - /')"

  if (( DRY_RUN == 1 )); then
    local dry="${TMPDIR:-/tmp}/Apple-AI-remover.$$.mobileconfig"
    build_profile "$dry" "$sets"
    info 'DRY RUN: no profile was installed and no model was reset.'
    info "generated profile: $dry"
    return 0
  fi

  confirm || { info 'Nothing changed.'; return 0; }

  local expected
  expected="$(keep_csv)"
  build_profile "$PROFILE_FILE" "$sets"
  open "$PROFILE_FILE" 2>/dev/null || true
  open_profile_settings
  info "Approve '$PROFILE_NAME' in System Settings."
  wait_for_profile "$expected" || fail 'profile installation was not observed; no model reset was attempted'

  if [[ -n "$sets" ]]; then
    if reset_models "$sets"; then
      info 'All selected model sets reset successfully.'
    else
      fail 'profile is installed, but one or more model resets failed; run status to inspect remaining model state'
    fi
  fi
  info "Done. Run: $0 status"
}

revert_command() {
  build_helper
  local current=0 legacy=0
  profile_installed && current=1
  legacy_profile_installed && legacy=1
  if (( current == 0 && legacy == 0 )); then info 'No Apple AI remover profile is installed.'; return 0; fi
  if (( YES == 0 )); then
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
  local f set x saved_keep all a b
  for f in "${FEATURES[@]}"; do
    feature_title "$f" >/dev/null || fail "missing title for $f"
    while IFS= read -r x; do
      [[ -z "$x" ]] && continue
      model_set_asset_type "$x" >/dev/null || fail "unknown model set $x referenced by $f"
    done < <(feature_model_sets "$f")
  done
  for set in "${MODEL_SETS[@]}"; do model_set_asset_type "$set" >/dev/null || fail "missing model-set mapping $set"; done

  saved_keep=("${KEEP[@]}")
  KEEP=()
  all="$(sets_to_remove)"
  [[ "$(printf '%s\n' "$all" | sort)" == "$(printf '%s\n' "${MODEL_SETS[@]}" | sort)" ]] || fail 'empty keep set must remove every model set'

  KEEP=(writing-tools)
  all="$(sets_to_remove)"
  ! grep -qx 'com.apple.modelcatalog' <<< "$all" || fail 'writing-tools must protect foundation models'
  grep -qx 'com.apple.MobileAsset.UAF.FM.Visual' <<< "$all" || fail 'writing-tools unexpectedly protects visual models'
  KEEP=("${saved_keep[@]}")

  a="$(stable_uuid "$PROFILE_ID")"; b="$(stable_uuid "$PROFILE_ID")"; [[ "$a" == "$b" ]] || fail 'payload UUID generator is not stable'
  printf 'selftest: PASS (%s features, %s model sets)\n' "${#FEATURES[@]}" "${#MODEL_SETS[@]}"
}

usage() {
  cat <<EOF_USAGE
$PRODUCT_NAME $VERSION

Usage:
  $0 status
  $0 features
  $0 off [--keep feature[,feature...]] [--dry-run] [--yes]
  $0 revert [--yes]
  $0 selftest

The mutating commands target macOS $TARGET_MAJOR.x on Apple silicon.
EOF_USAGE
}

main() {
  local command="${1:-status}"
  shift || true
  case "$command" in
    status) require_platform; status_command "$@" ;;
    features) [[ "$#" -eq 0 ]] || fail 'features takes no options'; print_features ;;
    off) require_platform; off_command "$@" ;;
    revert) require_platform; parse_args "$@"; revert_command ;;
    selftest) [[ "$#" -eq 0 ]] || fail 'selftest takes no options'; selftest_command ;;
    --help|-h|help) usage ;;
    --version|-v|version) echo "$VERSION" ;;
    *) usage >&2; exit 1 ;;
  esac
}

main "$@"
forced=1\tvalue=true'* ]]; }
upstream_profile_installed() { local o; o="$(helper_pref "$UPSTREAM_PROFILE_ID" installed 2>/dev/null)" || return 1; [[ "$o" == * { local o; o="$(helper_pref "$PROFILE_ID" kept 2>/dev/null)" || return 1; printf '%s' "${o#*value=}"; }

validate_uaf_catalog() {
  local set expected actual
  for set in "${MODEL_SETS[@]}"; do
    expected="$(model_set_asset_type "$set")"
    actual="$($HELPER asset-type "$set")" || fail "UAF asset-set lookup failed for $set"
    [[ "$actual" == "$expected" ]] || fail "UAF mapping mismatch for $set: expected $expected, got $actual"
  done
}

model_bytes() {
  local set="$1" out
  out="$($HELPER bytes "$set" 2>/dev/null)" || return 1
  [[ "$out" =~ ^[0-9]+$ ]] || return 1
  printf '%s' "$out"
}

format_bytes() {
  local b="$1"
  if (( b >= 1000000000 )); then awk -v n="$b" 'BEGIN { printf "%.1f GB", n/1e9 }'
  elif (( b > 0 )); then awk -v n="$b" 'BEGIN { printf "%.0f MB", n/1e6 }'
  else echo '0 MB'; fi
}

feature_state() {
  local feature="$1" domain key want output forced value
  local all=1 any=0
  while IFS=$'\t' read -r domain key want; do
    [[ -n "$domain" ]] || continue
    output="$(helper_pref "$domain" "$key" 2>/dev/null)" || { echo unknown; return; }
    forced="$(printf '%s' "$output" | sed -n 's/.*forced=\([^\t]*\).*/\1/p')"
    value="$(printf '%s' "$output" | sed -n 's/.*value=\([^\t]*\)$/\1/p')"
    [[ "$forced" == 1 && "$value" == "$want" ]] && any=1 || all=0
  done < <(feature_preferences "$feature")
  if (( all == 1 && any == 1 )); then echo locked; return; fi

  case "$feature" in
    chatgpt|writing-tools|genmoji|image-playground|safari-summaries|notes-summaries)
      local restricted_ok=1 r
      while IFS= read -r r; do
        [[ -n "$r" ]] || continue
        output="$(helper_pref com.apple.applicationaccess "$r" 2>/dev/null)" || { echo unknown; return; }
        [[ "$output" == *$'forced=1\tvalue=false'* ]] || restricted_ok=0
      done < <(feature_restrictions "$feature")
      (( restricted_ok == 1 )) && echo locked && return
      ;;
  esac

  if profile_installed && ! kept "$feature" && [[ -z "$(feature_preferences "$feature")" ]] && [[ -z "$(feature_restrictions "$feature")" ]]; then
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
  local feature state set n total=0
  for feature in "${FEATURES[@]}"; do
    state="$(feature_state "$feature")"
    printf '%-44s %s\n' "$(feature_title "$feature")" "$state"
  done
  printf '\nModels on disk\n'
  for set in "${MODEL_SETS[@]}"; do
    if n="$(model_bytes "$set")"; then
      total=$((total+n)); printf '  %-44s %s\n' "$(model_set_title "$set")" "$(format_bytes "$n")"
    else
      printf '  %-44s unknown\n' "$(model_set_title "$set")"
    fi
  done
  printf '  %-44s %s\n' Total "$(format_bytes "$total")"
  printf 'Profile: %s\n' "$(profile_installed && echo installed || echo not-installed)"
}

print_features() {
  local f
  for f in "${FEATURES[@]}"; do printf '%-28s %s\n' "$f" "$(feature_title "$f")"; done
}

open_profile_settings() {
  open 'x-apple.systempreferences:com.apple.Profiles-Settings.extension' 2>/dev/null || open 'x-apple.systempreferences:com.apple.preferences.configurationprofiles' 2>/dev/null || true
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
  printf 'Turn off Apple Intelligence and reset the selected models? [y/N] '
  read -r answer
  [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

off_command() {
  parse_args "$@"
  build_helper
  legacy_profile_installed && fail "legacy RemoveMacAI profile is installed; run '$0 revert' first"
  validate_uaf_catalog
  local sets
  sets="$(sets_to_remove)"

  printf 'Features to disable:\n'
  local f
  for f in "${FEATURES[@]}"; do kept "$f" || printf '  - %s\n' "$(feature_title "$f")"; done
  printf 'Model sets to reset:\n%s\n' "$(printf '%s\n' "$sets" | sed 's/^/  - /')"

  if (( DRY_RUN == 1 )); then
    local dry="${TMPDIR:-/tmp}/Apple-AI-remover.$$.mobileconfig"
    build_profile "$dry" "$sets"
    info 'DRY RUN: no profile was installed and no model was reset.'
    info "generated profile: $dry"
    return 0
  fi

  confirm || { info 'Nothing changed.'; return 0; }

  local expected
  expected="$(keep_csv)"
  build_profile "$PROFILE_FILE" "$sets"
  open "$PROFILE_FILE" 2>/dev/null || true
  open_profile_settings
  info "Approve '$PROFILE_NAME' in System Settings."
  wait_for_profile "$expected" || fail 'profile installation was not observed; no model reset was attempted'

  if [[ -n "$sets" ]]; then
    if reset_models "$sets"; then
      info 'All selected model sets reset successfully.'
    else
      fail 'profile is installed, but one or more model resets failed; run status to inspect remaining model state'
    fi
  fi
  info "Done. Run: $0 status"
}

revert_command() {
  build_helper
  local current=0 legacy=0
  profile_installed && current=1
  legacy_profile_installed && legacy=1
  if (( current == 0 && legacy == 0 )); then info 'No Apple AI remover profile is installed.'; return 0; fi
  if (( YES == 0 )); then
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
  local f set x saved_keep all a b
  for f in "${FEATURES[@]}"; do
    feature_title "$f" >/dev/null || fail "missing title for $f"
    while IFS= read -r x; do
      [[ -z "$x" ]] && continue
      model_set_asset_type "$x" >/dev/null || fail "unknown model set $x referenced by $f"
    done < <(feature_model_sets "$f")
  done
  for set in "${MODEL_SETS[@]}"; do model_set_asset_type "$set" >/dev/null || fail "missing model-set mapping $set"; done

  saved_keep=("${KEEP[@]}")
  KEEP=()
  all="$(sets_to_remove)"
  [[ "$(printf '%s\n' "$all" | sort)" == "$(printf '%s\n' "${MODEL_SETS[@]}" | sort)" ]] || fail 'empty keep set must remove every model set'

  KEEP=(writing-tools)
  all="$(sets_to_remove)"
  ! grep -qx 'com.apple.modelcatalog' <<< "$all" || fail 'writing-tools must protect foundation models'
  grep -qx 'com.apple.MobileAsset.UAF.FM.Visual' <<< "$all" || fail 'writing-tools unexpectedly protects visual models'
  KEEP=("${saved_keep[@]}")

  a="$(stable_uuid "$PROFILE_ID")"; b="$(stable_uuid "$PROFILE_ID")"; [[ "$a" == "$b" ]] || fail 'payload UUID generator is not stable'
  printf 'selftest: PASS (%s features, %s model sets)\n' "${#FEATURES[@]}" "${#MODEL_SETS[@]}"
}

usage() {
  cat <<EOF_USAGE
$PRODUCT_NAME $VERSION

Usage:
  $0 status
  $0 features
  $0 off [--keep feature[,feature...]] [--dry-run] [--yes]
  $0 revert [--yes]
  $0 selftest

The mutating commands target macOS $TARGET_MAJOR.x on Apple silicon.
EOF_USAGE
}

main() {
  local command="${1:-status}"
  shift || true
  case "$command" in
    status) require_platform; status_command "$@" ;;
    features) [[ "$#" -eq 0 ]] || fail 'features takes no options'; print_features ;;
    off) require_platform; off_command "$@" ;;
    revert) require_platform; parse_args "$@"; revert_command ;;
    selftest) [[ "$#" -eq 0 ]] || fail 'selftest takes no options'; selftest_command ;;
    --help|-h|help) usage ;;
    --version|-v|version) echo "$VERSION" ;;
    *) usage >&2; exit 1 ;;
  esac
}

main "$@"
\t'"${key}"
    [[ -n "$set" ]] || continue
    key="DownloadServerBaseURLOverride-$(model_set_asset_type "$set")"
    PREF_LINES="${PREF_LINES}com.apple.MobileAsset"$'\t'"${key}"$'\t'"${BLOCKED_URL}"$'\n'
  done <<< "$sets"

  mkdir -p "$(dirname "$output")"
  {
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
    printf '%s\n' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    printf '%s\n' '<plist version="1.0"><dict>'
    printf '%s\n' '<key>PayloadType</key><string>Configuration</string>'
    printf '%s\n' '<key>PayloadVersion</key><integer>1</integer>'
    printf '<key>PayloadIdentifier</key><string>%s</string>\n' "$PROFILE_ID"
    printf '<key>PayloadUUID</key><string>%s</string>\n' "$(stable_uuid "$PROFILE_ID")"
    printf '<key>PayloadDisplayName</key><string>%s</string>\n' "$(xml_escape "$PROFILE_NAME")"
    printf '%s\n' '<key>PayloadDescription</key><string>Disables Apple Intelligence features and prevents selected model sets from being re-downloaded. Remove this profile to undo.</string>'
    printf '%s\n' '<key>PayloadOrganization</key><string>Apple AI remover</string>'
    printf '%s\n' '<key>PayloadScope</key><string>System</string>'
    printf '%s\n' '<key>PayloadRemovalDisallowed</key><false/>'
    printf '%s\n' '<key>PayloadContent</key><array>'

    payload_header com.apple.applicationaccess restrictions 'Apple Intelligence restrictions'
    printf '%s\n' '      <key>PayloadContent</key><dict>'
    for feature in "${FEATURES[@]}"; do
      kept "$feature" && continue
      while IFS= read -r key; do
        [[ -n "$key" ]] && printf '        <key>%s</key><false/>\n' "$(xml_escape "$key")"
      done < <(feature_restrictions "$feature")
    done
    printf '%s\n' '      </dict>' '    </dict>'

    for d in com.apple.assistant.support com.apple.Siri group.com.apple.mail group.com.apple.usernoted com.apple.MobileSMS .GlobalPreferences com.apple.spatialphotosrelive; do
      PREF_LINES=''
      while IFS=$'\t' read -r domain key value; do
        [[ "$domain" == "$d" ]] || continue
        PREF_LINES="${PREF_LINES}${key}"$'\t'"${value}"$'\n'
      done <<< "$ALL_PREFS"
      append_pref_payload "$d" "$d" "Forced settings: $d"
    done

    PREF_LINES=''
    while IFS=$'\t' read -r domain key value; do
      [[ "$domain" == 'com.apple.MobileAsset' ]] || continue
      PREF_LINES="${PREF_LINES}${key}"$'\t'"${value}"$'\n'
    done <<< "$ALL_PREFS"
    append_pref_payload com.apple.MobileAsset MobileAsset 'MobileAsset download overrides'

    PREF_LINES="installed"$'\t'true$'\n'"kept"$'\t'"$(keep_csv)"$'\n'
    append_pref_payload "$PROFILE_ID" marker 'Apple AI remover state'

    printf '%s\n' '</array></dict></plist>'
  } > "$tmp"
  /usr/bin/plutil -lint "$tmp" >/dev/null 2>&1 || { rm -f "$tmp"; fail 'generated profile failed plist validation'; }
  mv "$tmp" "$output"
}

keep_csv() {
  local out='' item
  for item in "${KEEP[@]}"; do
    [[ -n "$out" ]] && out="$out,"
    out="$out$item"
  done
  printf '%s' "$out"
}

helper_pref() { "$HELPER" pref "$1" "$2"; }
profile_installed() { local o; o="$(helper_pref "$PROFILE_ID" installed 2>/dev/null)" || return 1; [[ "$o" == *$'forced=1\tvalue=true'* ]]; }
legacy_profile_installed() { local o; o="$(helper_pref "$LEGACY_PROFILE_ID" installed 2>/dev/null)" || return 1; [[ "$o" == *$'forced=1\tvalue=true'* ]]; }
profile_kept_csv() { local o; o="$(helper_pref "$PROFILE_ID" kept 2>/dev/null)" || return 1; printf '%s' "${o#*value=}"; }

validate_uaf_catalog() {
  local set expected actual
  for set in "${MODEL_SETS[@]}"; do
    expected="$(model_set_asset_type "$set")"
    actual="$($HELPER asset-type "$set")" || fail "UAF asset-set lookup failed for $set"
    [[ "$actual" == "$expected" ]] || fail "UAF mapping mismatch for $set: expected $expected, got $actual"
  done
}

model_bytes() {
  local set="$1" out
  out="$($HELPER bytes "$set" 2>/dev/null)" || return 1
  [[ "$out" =~ ^[0-9]+$ ]] || return 1
  printf '%s' "$out"
}

format_bytes() {
  local b="$1"
  if (( b >= 1000000000 )); then awk -v n="$b" 'BEGIN { printf "%.1f GB", n/1e9 }'
  elif (( b > 0 )); then awk -v n="$b" 'BEGIN { printf "%.0f MB", n/1e6 }'
  else echo '0 MB'; fi
}

feature_state() {
  local feature="$1" domain key want output forced value
  local all=1 any=0
  while IFS=$'\t' read -r domain key want; do
    [[ -n "$domain" ]] || continue
    output="$(helper_pref "$domain" "$key" 2>/dev/null)" || { echo unknown; return; }
    forced="$(printf '%s' "$output" | sed -n 's/.*forced=\([^\t]*\).*/\1/p')"
    value="$(printf '%s' "$output" | sed -n 's/.*value=\([^\t]*\)$/\1/p')"
    [[ "$forced" == 1 && "$value" == "$want" ]] && any=1 || all=0
  done < <(feature_preferences "$feature")
  if (( all == 1 && any == 1 )); then echo locked; return; fi

  case "$feature" in
    chatgpt|writing-tools|genmoji|image-playground|safari-summaries|notes-summaries)
      local restricted_ok=1 r
      while IFS= read -r r; do
        [[ -n "$r" ]] || continue
        output="$(helper_pref com.apple.applicationaccess "$r" 2>/dev/null)" || { echo unknown; return; }
        [[ "$output" == *$'forced=1\tvalue=false'* ]] || restricted_ok=0
      done < <(feature_restrictions "$feature")
      (( restricted_ok == 1 )) && echo locked && return
      ;;
  esac

  if profile_installed && ! kept "$feature" && [[ -z "$(feature_preferences "$feature")" ]] && [[ -z "$(feature_restrictions "$feature")" ]]; then
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
  local feature state set n total=0
  for feature in "${FEATURES[@]}"; do
    state="$(feature_state "$feature")"
    printf '%-44s %s\n' "$(feature_title "$feature")" "$state"
  done
  printf '\nModels on disk\n'
  for set in "${MODEL_SETS[@]}"; do
    if n="$(model_bytes "$set")"; then
      total=$((total+n)); printf '  %-44s %s\n' "$(model_set_title "$set")" "$(format_bytes "$n")"
    else
      printf '  %-44s unknown\n' "$(model_set_title "$set")"
    fi
  done
  printf '  %-44s %s\n' Total "$(format_bytes "$total")"
  printf 'Profile: %s\n' "$(profile_installed && echo installed || echo not-installed)"
}

print_features() {
  local f
  for f in "${FEATURES[@]}"; do printf '%-28s %s\n' "$f" "$(feature_title "$f")"; done
}

open_profile_settings() {
  open 'x-apple.systempreferences:com.apple.Profiles-Settings.extension' 2>/dev/null || open 'x-apple.systempreferences:com.apple.preferences.configurationprofiles' 2>/dev/null || true
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
  printf 'Turn off Apple Intelligence and reset the selected models? [y/N] '
  read -r answer
  [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

off_command() {
  parse_args "$@"
  build_helper
  legacy_profile_installed && fail "legacy RemoveMacAI profile is installed; run '$0 revert' first"
  validate_uaf_catalog
  local sets
  sets="$(sets_to_remove)"

  printf 'Features to disable:\n'
  local f
  for f in "${FEATURES[@]}"; do kept "$f" || printf '  - %s\n' "$(feature_title "$f")"; done
  printf 'Model sets to reset:\n%s\n' "$(printf '%s\n' "$sets" | sed 's/^/  - /')"

  if (( DRY_RUN == 1 )); then
    local dry="${TMPDIR:-/tmp}/Apple-AI-remover.$$.mobileconfig"
    build_profile "$dry" "$sets"
    info 'DRY RUN: no profile was installed and no model was reset.'
    info "generated profile: $dry"
    return 0
  fi

  confirm || { info 'Nothing changed.'; return 0; }

  local expected
  expected="$(keep_csv)"
  build_profile "$PROFILE_FILE" "$sets"
  open "$PROFILE_FILE" 2>/dev/null || true
  open_profile_settings
  info "Approve '$PROFILE_NAME' in System Settings."
  wait_for_profile "$expected" || fail 'profile installation was not observed; no model reset was attempted'

  if [[ -n "$sets" ]]; then
    if reset_models "$sets"; then
      info 'All selected model sets reset successfully.'
    else
      fail 'profile is installed, but one or more model resets failed; run status to inspect remaining model state'
    fi
  fi
  info "Done. Run: $0 status"
}

revert_command() {
  build_helper
  local current=0 legacy=0
  profile_installed && current=1
  legacy_profile_installed && legacy=1
  if (( current == 0 && legacy == 0 )); then info 'No Apple AI remover profile is installed.'; return 0; fi
  if (( YES == 0 )); then
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
  local f set x saved_keep all a b
  for f in "${FEATURES[@]}"; do
    feature_title "$f" >/dev/null || fail "missing title for $f"
    while IFS= read -r x; do
      [[ -z "$x" ]] && continue
      model_set_asset_type "$x" >/dev/null || fail "unknown model set $x referenced by $f"
    done < <(feature_model_sets "$f")
  done
  for set in "${MODEL_SETS[@]}"; do model_set_asset_type "$set" >/dev/null || fail "missing model-set mapping $set"; done

  saved_keep=("${KEEP[@]}")
  KEEP=()
  all="$(sets_to_remove)"
  [[ "$(printf '%s\n' "$all" | sort)" == "$(printf '%s\n' "${MODEL_SETS[@]}" | sort)" ]] || fail 'empty keep set must remove every model set'

  KEEP=(writing-tools)
  all="$(sets_to_remove)"
  ! grep -qx 'com.apple.modelcatalog' <<< "$all" || fail 'writing-tools must protect foundation models'
  grep -qx 'com.apple.MobileAsset.UAF.FM.Visual' <<< "$all" || fail 'writing-tools unexpectedly protects visual models'
  KEEP=("${saved_keep[@]}")

  a="$(stable_uuid "$PROFILE_ID")"; b="$(stable_uuid "$PROFILE_ID")"; [[ "$a" == "$b" ]] || fail 'payload UUID generator is not stable'
  printf 'selftest: PASS (%s features, %s model sets)\n' "${#FEATURES[@]}" "${#MODEL_SETS[@]}"
}

usage() {
  cat <<EOF_USAGE
$PRODUCT_NAME $VERSION

Usage:
  $0 status
  $0 features
  $0 off [--keep feature[,feature...]] [--dry-run] [--yes]
  $0 revert [--yes]
  $0 selftest

The mutating commands target macOS $TARGET_MAJOR.x on Apple silicon.
EOF_USAGE
}

main() {
  local command="${1:-status}"
  shift || true
  case "$command" in
    status) require_platform; status_command "$@" ;;
    features) [[ "$#" -eq 0 ]] || fail 'features takes no options'; print_features ;;
    off) require_platform; off_command "$@" ;;
    revert) require_platform; parse_args "$@"; revert_command ;;
    selftest) [[ "$#" -eq 0 ]] || fail 'selftest takes no options'; selftest_command ;;
    --help|-h|help) usage ;;
    --version|-v|version) echo "$VERSION" ;;
    *) usage >&2; exit 1 ;;
  esac
}

main "$@"
\t'"${value}"
    [[ -n "$set" ]] || continue
    key="DownloadServerBaseURLOverride-$(model_set_asset_type "$set")"
    PREF_LINES="${PREF_LINES}com.apple.MobileAsset"$'\t'"${key}"$'\t'"${BLOCKED_URL}"$'\n'
  done <<< "$sets"

  mkdir -p "$(dirname "$output")"
  {
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
    printf '%s\n' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    printf '%s\n' '<plist version="1.0"><dict>'
    printf '%s\n' '<key>PayloadType</key><string>Configuration</string>'
    printf '%s\n' '<key>PayloadVersion</key><integer>1</integer>'
    printf '<key>PayloadIdentifier</key><string>%s</string>\n' "$PROFILE_ID"
    printf '<key>PayloadUUID</key><string>%s</string>\n' "$(stable_uuid "$PROFILE_ID")"
    printf '<key>PayloadDisplayName</key><string>%s</string>\n' "$(xml_escape "$PROFILE_NAME")"
    printf '%s\n' '<key>PayloadDescription</key><string>Disables Apple Intelligence features and prevents selected model sets from being re-downloaded. Remove this profile to undo.</string>'
    printf '%s\n' '<key>PayloadOrganization</key><string>Apple AI remover</string>'
    printf '%s\n' '<key>PayloadScope</key><string>System</string>'
    printf '%s\n' '<key>PayloadRemovalDisallowed</key><false/>'
    printf '%s\n' '<key>PayloadContent</key><array>'

    payload_header com.apple.applicationaccess restrictions 'Apple Intelligence restrictions'
    printf '%s\n' '      <key>PayloadContent</key><dict>'
    for feature in "${FEATURES[@]}"; do
      kept "$feature" && continue
      while IFS= read -r key; do
        [[ -n "$key" ]] && printf '        <key>%s</key><false/>\n' "$(xml_escape "$key")"
      done < <(feature_restrictions "$feature")
    done
    printf '%s\n' '      </dict>' '    </dict>'

    for d in com.apple.assistant.support com.apple.Siri group.com.apple.mail group.com.apple.usernoted com.apple.MobileSMS .GlobalPreferences com.apple.spatialphotosrelive; do
      PREF_LINES=''
      while IFS=$'\t' read -r domain key value; do
        [[ "$domain" == "$d" ]] || continue
        PREF_LINES="${PREF_LINES}${key}"$'\t'"${value}"$'\n'
      done <<< "$ALL_PREFS"
      append_pref_payload "$d" "$d" "Forced settings: $d"
    done

    PREF_LINES=''
    while IFS=$'\t' read -r domain key value; do
      [[ "$domain" == 'com.apple.MobileAsset' ]] || continue
      PREF_LINES="${PREF_LINES}${key}"$'\t'"${value}"$'\n'
    done <<< "$ALL_PREFS"
    append_pref_payload com.apple.MobileAsset MobileAsset 'MobileAsset download overrides'

    PREF_LINES="installed"$'\t'true$'\n'"kept"$'\t'"$(keep_csv)"$'\n'
    append_pref_payload "$PROFILE_ID" marker 'Apple AI remover state'

    printf '%s\n' '</array></dict></plist>'
  } > "$tmp"
  /usr/bin/plutil -lint "$tmp" >/dev/null 2>&1 || { rm -f "$tmp"; fail 'generated profile failed plist validation'; }
  mv "$tmp" "$output"
}

keep_csv() {
  local out='' item
  for item in "${KEEP[@]}"; do
    [[ -n "$out" ]] && out="$out,"
    out="$out$item"
  done
  printf '%s' "$out"
}

helper_pref() { "$HELPER" pref "$1" "$2"; }
profile_installed() { local o; o="$(helper_pref "$PROFILE_ID" installed 2>/dev/null)" || return 1; [[ "$o" == *$'forced=1\tvalue=true'* ]]; }
legacy_profile_installed() { local o; o="$(helper_pref "$LEGACY_PROFILE_ID" installed 2>/dev/null)" || return 1; [[ "$o" == *$'forced=1\tvalue=true'* ]]; }
profile_kept_csv() { local o; o="$(helper_pref "$PROFILE_ID" kept 2>/dev/null)" || return 1; printf '%s' "${o#*value=}"; }

validate_uaf_catalog() {
  local set expected actual
  for set in "${MODEL_SETS[@]}"; do
    expected="$(model_set_asset_type "$set")"
    actual="$($HELPER asset-type "$set")" || fail "UAF asset-set lookup failed for $set"
    [[ "$actual" == "$expected" ]] || fail "UAF mapping mismatch for $set: expected $expected, got $actual"
  done
}

model_bytes() {
  local set="$1" out
  out="$($HELPER bytes "$set" 2>/dev/null)" || return 1
  [[ "$out" =~ ^[0-9]+$ ]] || return 1
  printf '%s' "$out"
}

format_bytes() {
  local b="$1"
  if (( b >= 1000000000 )); then awk -v n="$b" 'BEGIN { printf "%.1f GB", n/1e9 }'
  elif (( b > 0 )); then awk -v n="$b" 'BEGIN { printf "%.0f MB", n/1e6 }'
  else echo '0 MB'; fi
}

feature_state() {
  local feature="$1" domain key want output forced value
  local all=1 any=0
  while IFS=$'\t' read -r domain key want; do
    [[ -n "$domain" ]] || continue
    output="$(helper_pref "$domain" "$key" 2>/dev/null)" || { echo unknown; return; }
    forced="$(printf '%s' "$output" | sed -n 's/.*forced=\([^\t]*\).*/\1/p')"
    value="$(printf '%s' "$output" | sed -n 's/.*value=\([^\t]*\)$/\1/p')"
    [[ "$forced" == 1 && "$value" == "$want" ]] && any=1 || all=0
  done < <(feature_preferences "$feature")
  if (( all == 1 && any == 1 )); then echo locked; return; fi

  case "$feature" in
    chatgpt|writing-tools|genmoji|image-playground|safari-summaries|notes-summaries)
      local restricted_ok=1 r
      while IFS= read -r r; do
        [[ -n "$r" ]] || continue
        output="$(helper_pref com.apple.applicationaccess "$r" 2>/dev/null)" || { echo unknown; return; }
        [[ "$output" == *$'forced=1\tvalue=false'* ]] || restricted_ok=0
      done < <(feature_restrictions "$feature")
      (( restricted_ok == 1 )) && echo locked && return
      ;;
  esac

  if profile_installed && ! kept "$feature" && [[ -z "$(feature_preferences "$feature")" ]] && [[ -z "$(feature_restrictions "$feature")" ]]; then
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
  local feature state set n total=0
  for feature in "${FEATURES[@]}"; do
    state="$(feature_state "$feature")"
    printf '%-44s %s\n' "$(feature_title "$feature")" "$state"
  done
  printf '\nModels on disk\n'
  for set in "${MODEL_SETS[@]}"; do
    if n="$(model_bytes "$set")"; then
      total=$((total+n)); printf '  %-44s %s\n' "$(model_set_title "$set")" "$(format_bytes "$n")"
    else
      printf '  %-44s unknown\n' "$(model_set_title "$set")"
    fi
  done
  printf '  %-44s %s\n' Total "$(format_bytes "$total")"
  printf 'Profile: %s\n' "$(profile_installed && echo installed || echo not-installed)"
}

print_features() {
  local f
  for f in "${FEATURES[@]}"; do printf '%-28s %s\n' "$f" "$(feature_title "$f")"; done
}

open_profile_settings() {
  open 'x-apple.systempreferences:com.apple.Profiles-Settings.extension' 2>/dev/null || open 'x-apple.systempreferences:com.apple.preferences.configurationprofiles' 2>/dev/null || true
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
  printf 'Turn off Apple Intelligence and reset the selected models? [y/N] '
  read -r answer
  [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

off_command() {
  parse_args "$@"
  build_helper
  legacy_profile_installed && fail "legacy RemoveMacAI profile is installed; run '$0 revert' first"
  validate_uaf_catalog
  local sets
  sets="$(sets_to_remove)"

  printf 'Features to disable:\n'
  local f
  for f in "${FEATURES[@]}"; do kept "$f" || printf '  - %s\n' "$(feature_title "$f")"; done
  printf 'Model sets to reset:\n%s\n' "$(printf '%s\n' "$sets" | sed 's/^/  - /')"

  if (( DRY_RUN == 1 )); then
    local dry="${TMPDIR:-/tmp}/Apple-AI-remover.$$.mobileconfig"
    build_profile "$dry" "$sets"
    info 'DRY RUN: no profile was installed and no model was reset.'
    info "generated profile: $dry"
    return 0
  fi

  confirm || { info 'Nothing changed.'; return 0; }

  local expected
  expected="$(keep_csv)"
  build_profile "$PROFILE_FILE" "$sets"
  open "$PROFILE_FILE" 2>/dev/null || true
  open_profile_settings
  info "Approve '$PROFILE_NAME' in System Settings."
  wait_for_profile "$expected" || fail 'profile installation was not observed; no model reset was attempted'

  if [[ -n "$sets" ]]; then
    if reset_models "$sets"; then
      info 'All selected model sets reset successfully.'
    else
      fail 'profile is installed, but one or more model resets failed; run status to inspect remaining model state'
    fi
  fi
  info "Done. Run: $0 status"
}

revert_command() {
  build_helper
  local current=0 legacy=0
  profile_installed && current=1
  legacy_profile_installed && legacy=1
  if (( current == 0 && legacy == 0 )); then info 'No Apple AI remover profile is installed.'; return 0; fi
  if (( YES == 0 )); then
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
  local f set x saved_keep all a b
  for f in "${FEATURES[@]}"; do
    feature_title "$f" >/dev/null || fail "missing title for $f"
    while IFS= read -r x; do
      [[ -z "$x" ]] && continue
      model_set_asset_type "$x" >/dev/null || fail "unknown model set $x referenced by $f"
    done < <(feature_model_sets "$f")
  done
  for set in "${MODEL_SETS[@]}"; do model_set_asset_type "$set" >/dev/null || fail "missing model-set mapping $set"; done

  saved_keep=("${KEEP[@]}")
  KEEP=()
  all="$(sets_to_remove)"
  [[ "$(printf '%s\n' "$all" | sort)" == "$(printf '%s\n' "${MODEL_SETS[@]}" | sort)" ]] || fail 'empty keep set must remove every model set'

  KEEP=(writing-tools)
  all="$(sets_to_remove)"
  ! grep -qx 'com.apple.modelcatalog' <<< "$all" || fail 'writing-tools must protect foundation models'
  grep -qx 'com.apple.MobileAsset.UAF.FM.Visual' <<< "$all" || fail 'writing-tools unexpectedly protects visual models'
  KEEP=("${saved_keep[@]}")

  a="$(stable_uuid "$PROFILE_ID")"; b="$(stable_uuid "$PROFILE_ID")"; [[ "$a" == "$b" ]] || fail 'payload UUID generator is not stable'
  printf 'selftest: PASS (%s features, %s model sets)\n' "${#FEATURES[@]}" "${#MODEL_SETS[@]}"
}

usage() {
  cat <<EOF_USAGE
$PRODUCT_NAME $VERSION

Usage:
  $0 status
  $0 features
  $0 off [--keep feature[,feature...]] [--dry-run] [--yes]
  $0 revert [--yes]
  $0 selftest

The mutating commands target macOS $TARGET_MAJOR.x on Apple silicon.
EOF_USAGE
}

main() {
  local command="${1:-status}"
  shift || true
  case "$command" in
    status) require_platform; status_command "$@" ;;
    features) [[ "$#" -eq 0 ]] || fail 'features takes no options'; print_features ;;
    off) require_platform; off_command "$@" ;;
    revert) require_platform; parse_args "$@"; revert_command ;;
    selftest) [[ "$#" -eq 0 ]] || fail 'selftest takes no options'; selftest_command ;;
    --help|-h|help) usage ;;
    --version|-v|version) echo "$VERSION" ;;
    *) usage >&2; exit 1 ;;
  esac
}

main "$@"
\n'
    done < <(feature_preferences "$feature")
  done
  while IFS= read -r set; do
    [[ -n "$set" ]] || continue
    key="DownloadServerBaseURLOverride-$(model_set_asset_type "$set")"
    PREF_LINES="${PREF_LINES}com.apple.MobileAsset"$'\t'"${key}"$'\t'"${BLOCKED_URL}"$'\n'
  done <<< "$sets"

  mkdir -p "$(dirname "$output")"
  {
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
    printf '%s\n' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    printf '%s\n' '<plist version="1.0"><dict>'
    printf '%s\n' '<key>PayloadType</key><string>Configuration</string>'
    printf '%s\n' '<key>PayloadVersion</key><integer>1</integer>'
    printf '<key>PayloadIdentifier</key><string>%s</string>\n' "$PROFILE_ID"
    printf '<key>PayloadUUID</key><string>%s</string>\n' "$(stable_uuid "$PROFILE_ID")"
    printf '<key>PayloadDisplayName</key><string>%s</string>\n' "$(xml_escape "$PROFILE_NAME")"
    printf '%s\n' '<key>PayloadDescription</key><string>Disables Apple Intelligence features and prevents selected model sets from being re-downloaded. Remove this profile to undo.</string>'
    printf '%s\n' '<key>PayloadOrganization</key><string>Apple AI remover</string>'
    printf '%s\n' '<key>PayloadScope</key><string>System</string>'
    printf '%s\n' '<key>PayloadRemovalDisallowed</key><false/>'
    printf '%s\n' '<key>PayloadContent</key><array>'

    payload_header com.apple.applicationaccess restrictions 'Apple Intelligence restrictions'
    printf '%s\n' '      <key>PayloadContent</key><dict>'
    for feature in "${FEATURES[@]}"; do
      kept "$feature" && continue
      while IFS= read -r key; do
        [[ -n "$key" ]] && printf '        <key>%s</key><false/>\n' "$(xml_escape "$key")"
      done < <(feature_restrictions "$feature")
    done
    printf '%s\n' '      </dict>' '    </dict>'

    for d in com.apple.assistant.support com.apple.Siri group.com.apple.mail group.com.apple.usernoted com.apple.MobileSMS .GlobalPreferences com.apple.spatialphotosrelive; do
      PREF_LINES=''
      while IFS=$'\t' read -r domain key value; do
        [[ "$domain" == "$d" ]] || continue
        PREF_LINES="${PREF_LINES}${key}"$'\t'"${value}"$'\n'
      done <<< "$ALL_PREFS"
      append_pref_payload "$d" "$d" "Forced settings: $d"
    done

    PREF_LINES=''
    while IFS=$'\t' read -r domain key value; do
      [[ "$domain" == 'com.apple.MobileAsset' ]] || continue
      PREF_LINES="${PREF_LINES}${key}"$'\t'"${value}"$'\n'
    done <<< "$ALL_PREFS"
    append_pref_payload com.apple.MobileAsset MobileAsset 'MobileAsset download overrides'

    PREF_LINES="installed"$'\t'true$'\n'"kept"$'\t'"$(keep_csv)"$'\n'
    append_pref_payload "$PROFILE_ID" marker 'Apple AI remover state'

    printf '%s\n' '</array></dict></plist>'
  } > "$tmp"
  /usr/bin/plutil -lint "$tmp" >/dev/null 2>&1 || { rm -f "$tmp"; fail 'generated profile failed plist validation'; }
  mv "$tmp" "$output"
}

keep_csv() {
  local out='' item
  for item in "${KEEP[@]}"; do
    [[ -n "$out" ]] && out="$out,"
    out="$out$item"
  done
  printf '%s' "$out"
}

helper_pref() { "$HELPER" pref "$1" "$2"; }
profile_installed() { local o; o="$(helper_pref "$PROFILE_ID" installed 2>/dev/null)" || return 1; [[ "$o" == *$'forced=1\tvalue=true'* ]]; }
legacy_profile_installed() { local o; o="$(helper_pref "$LEGACY_PROFILE_ID" installed 2>/dev/null)" || return 1; [[ "$o" == *$'forced=1\tvalue=true'* ]]; }
profile_kept_csv() { local o; o="$(helper_pref "$PROFILE_ID" kept 2>/dev/null)" || return 1; printf '%s' "${o#*value=}"; }

validate_uaf_catalog() {
  local set expected actual
  for set in "${MODEL_SETS[@]}"; do
    expected="$(model_set_asset_type "$set")"
    actual="$($HELPER asset-type "$set")" || fail "UAF asset-set lookup failed for $set"
    [[ "$actual" == "$expected" ]] || fail "UAF mapping mismatch for $set: expected $expected, got $actual"
  done
}

model_bytes() {
  local set="$1" out
  out="$($HELPER bytes "$set" 2>/dev/null)" || return 1
  [[ "$out" =~ ^[0-9]+$ ]] || return 1
  printf '%s' "$out"
}

format_bytes() {
  local b="$1"
  if (( b >= 1000000000 )); then awk -v n="$b" 'BEGIN { printf "%.1f GB", n/1e9 }'
  elif (( b > 0 )); then awk -v n="$b" 'BEGIN { printf "%.0f MB", n/1e6 }'
  else echo '0 MB'; fi
}

feature_state() {
  local feature="$1" domain key want output forced value
  local all=1 any=0
  while IFS=$'\t' read -r domain key want; do
    [[ -n "$domain" ]] || continue
    output="$(helper_pref "$domain" "$key" 2>/dev/null)" || { echo unknown; return; }
    forced="$(printf '%s' "$output" | sed -n 's/.*forced=\([^\t]*\).*/\1/p')"
    value="$(printf '%s' "$output" | sed -n 's/.*value=\([^\t]*\)$/\1/p')"
    [[ "$forced" == 1 && "$value" == "$want" ]] && any=1 || all=0
  done < <(feature_preferences "$feature")
  if (( all == 1 && any == 1 )); then echo locked; return; fi

  case "$feature" in
    chatgpt|writing-tools|genmoji|image-playground|safari-summaries|notes-summaries)
      local restricted_ok=1 r
      while IFS= read -r r; do
        [[ -n "$r" ]] || continue
        output="$(helper_pref com.apple.applicationaccess "$r" 2>/dev/null)" || { echo unknown; return; }
        [[ "$output" == *$'forced=1\tvalue=false'* ]] || restricted_ok=0
      done < <(feature_restrictions "$feature")
      (( restricted_ok == 1 )) && echo locked && return
      ;;
  esac

  if profile_installed && ! kept "$feature" && [[ -z "$(feature_preferences "$feature")" ]] && [[ -z "$(feature_restrictions "$feature")" ]]; then
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
  local feature state set n total=0
  for feature in "${FEATURES[@]}"; do
    state="$(feature_state "$feature")"
    printf '%-44s %s\n' "$(feature_title "$feature")" "$state"
  done
  printf '\nModels on disk\n'
  for set in "${MODEL_SETS[@]}"; do
    if n="$(model_bytes "$set")"; then
      total=$((total+n)); printf '  %-44s %s\n' "$(model_set_title "$set")" "$(format_bytes "$n")"
    else
      printf '  %-44s unknown\n' "$(model_set_title "$set")"
    fi
  done
  printf '  %-44s %s\n' Total "$(format_bytes "$total")"
  printf 'Profile: %s\n' "$(profile_installed && echo installed || echo not-installed)"
}

print_features() {
  local f
  for f in "${FEATURES[@]}"; do printf '%-28s %s\n' "$f" "$(feature_title "$f")"; done
}

open_profile_settings() {
  open 'x-apple.systempreferences:com.apple.Profiles-Settings.extension' 2>/dev/null || open 'x-apple.systempreferences:com.apple.preferences.configurationprofiles' 2>/dev/null || true
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
  printf 'Turn off Apple Intelligence and reset the selected models? [y/N] '
  read -r answer
  [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

off_command() {
  parse_args "$@"
  build_helper
  legacy_profile_installed && fail "legacy RemoveMacAI profile is installed; run '$0 revert' first"
  validate_uaf_catalog
  local sets
  sets="$(sets_to_remove)"

  printf 'Features to disable:\n'
  local f
  for f in "${FEATURES[@]}"; do kept "$f" || printf '  - %s\n' "$(feature_title "$f")"; done
  printf 'Model sets to reset:\n%s\n' "$(printf '%s\n' "$sets" | sed 's/^/  - /')"

  if (( DRY_RUN == 1 )); then
    local dry="${TMPDIR:-/tmp}/Apple-AI-remover.$$.mobileconfig"
    build_profile "$dry" "$sets"
    info 'DRY RUN: no profile was installed and no model was reset.'
    info "generated profile: $dry"
    return 0
  fi

  confirm || { info 'Nothing changed.'; return 0; }

  local expected
  expected="$(keep_csv)"
  build_profile "$PROFILE_FILE" "$sets"
  open "$PROFILE_FILE" 2>/dev/null || true
  open_profile_settings
  info "Approve '$PROFILE_NAME' in System Settings."
  wait_for_profile "$expected" || fail 'profile installation was not observed; no model reset was attempted'

  if [[ -n "$sets" ]]; then
    if reset_models "$sets"; then
      info 'All selected model sets reset successfully.'
    else
      fail 'profile is installed, but one or more model resets failed; run status to inspect remaining model state'
    fi
  fi
  info "Done. Run: $0 status"
}

revert_command() {
  build_helper
  local current=0 legacy=0
  profile_installed && current=1
  legacy_profile_installed && legacy=1
  if (( current == 0 && legacy == 0 )); then info 'No Apple AI remover profile is installed.'; return 0; fi
  if (( YES == 0 )); then
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
  local f set x saved_keep all a b
  for f in "${FEATURES[@]}"; do
    feature_title "$f" >/dev/null || fail "missing title for $f"
    while IFS= read -r x; do
      [[ -z "$x" ]] && continue
      model_set_asset_type "$x" >/dev/null || fail "unknown model set $x referenced by $f"
    done < <(feature_model_sets "$f")
  done
  for set in "${MODEL_SETS[@]}"; do model_set_asset_type "$set" >/dev/null || fail "missing model-set mapping $set"; done

  saved_keep=("${KEEP[@]}")
  KEEP=()
  all="$(sets_to_remove)"
  [[ "$(printf '%s\n' "$all" | sort)" == "$(printf '%s\n' "${MODEL_SETS[@]}" | sort)" ]] || fail 'empty keep set must remove every model set'

  KEEP=(writing-tools)
  all="$(sets_to_remove)"
  ! grep -qx 'com.apple.modelcatalog' <<< "$all" || fail 'writing-tools must protect foundation models'
  grep -qx 'com.apple.MobileAsset.UAF.FM.Visual' <<< "$all" || fail 'writing-tools unexpectedly protects visual models'
  KEEP=("${saved_keep[@]}")

  a="$(stable_uuid "$PROFILE_ID")"; b="$(stable_uuid "$PROFILE_ID")"; [[ "$a" == "$b" ]] || fail 'payload UUID generator is not stable'
  printf 'selftest: PASS (%s features, %s model sets)\n' "${#FEATURES[@]}" "${#MODEL_SETS[@]}"
}

usage() {
  cat <<EOF_USAGE
$PRODUCT_NAME $VERSION

Usage:
  $0 status
  $0 features
  $0 off [--keep feature[,feature...]] [--dry-run] [--yes]
  $0 revert [--yes]
  $0 selftest

The mutating commands target macOS $TARGET_MAJOR.x on Apple silicon.
EOF_USAGE
}

main() {
  local command="${1:-status}"
  shift || true
  case "$command" in
    status) require_platform; status_command "$@" ;;
    features) [[ "$#" -eq 0 ]] || fail 'features takes no options'; print_features ;;
    off) require_platform; off_command "$@" ;;
    revert) require_platform; parse_args "$@"; revert_command ;;
    selftest) [[ "$#" -eq 0 ]] || fail 'selftest takes no options'; selftest_command ;;
    --help|-h|help) usage ;;
    --version|-v|version) echo "$VERSION" ;;
    *) usage >&2; exit 1 ;;
  esac
}

main "$@"
forced=1\tvalue=true'* ]]; }
profile_kept_csv() { local o; o="$(helper_pref "$PROFILE_ID" kept 2>/dev/null)" || return 1; printf '%s' "${o#*value=}"; }

validate_uaf_catalog() {
  local set expected actual
  for set in "${MODEL_SETS[@]}"; do
    expected="$(model_set_asset_type "$set")"
    actual="$($HELPER asset-type "$set")" || fail "UAF asset-set lookup failed for $set"
    [[ "$actual" == "$expected" ]] || fail "UAF mapping mismatch for $set: expected $expected, got $actual"
  done
}

model_bytes() {
  local set="$1" out
  out="$($HELPER bytes "$set" 2>/dev/null)" || return 1
  [[ "$out" =~ ^[0-9]+$ ]] || return 1
  printf '%s' "$out"
}

format_bytes() {
  local b="$1"
  if (( b >= 1000000000 )); then awk -v n="$b" 'BEGIN { printf "%.1f GB", n/1e9 }'
  elif (( b > 0 )); then awk -v n="$b" 'BEGIN { printf "%.0f MB", n/1e6 }'
  else echo '0 MB'; fi
}

feature_state() {
  local feature="$1" domain key want output forced value
  local all=1 any=0
  while IFS=$'\t' read -r domain key want; do
    [[ -n "$domain" ]] || continue
    output="$(helper_pref "$domain" "$key" 2>/dev/null)" || { echo unknown; return; }
    forced="$(printf '%s' "$output" | sed -n 's/.*forced=\([^\t]*\).*/\1/p')"
    value="$(printf '%s' "$output" | sed -n 's/.*value=\([^\t]*\)$/\1/p')"
    [[ "$forced" == 1 && "$value" == "$want" ]] && any=1 || all=0
  done < <(feature_preferences "$feature")
  if (( all == 1 && any == 1 )); then echo locked; return; fi

  case "$feature" in
    chatgpt|writing-tools|genmoji|image-playground|safari-summaries|notes-summaries)
      local restricted_ok=1 r
      while IFS= read -r r; do
        [[ -n "$r" ]] || continue
        output="$(helper_pref com.apple.applicationaccess "$r" 2>/dev/null)" || { echo unknown; return; }
        [[ "$output" == *$'forced=1\tvalue=false'* ]] || restricted_ok=0
      done < <(feature_restrictions "$feature")
      (( restricted_ok == 1 )) && echo locked && return
      ;;
  esac

  if profile_installed && ! kept "$feature" && [[ -z "$(feature_preferences "$feature")" ]] && [[ -z "$(feature_restrictions "$feature")" ]]; then
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
  local feature state set n total=0
  for feature in "${FEATURES[@]}"; do
    state="$(feature_state "$feature")"
    printf '%-44s %s\n' "$(feature_title "$feature")" "$state"
  done
  printf '\nModels on disk\n'
  for set in "${MODEL_SETS[@]}"; do
    if n="$(model_bytes "$set")"; then
      total=$((total+n)); printf '  %-44s %s\n' "$(model_set_title "$set")" "$(format_bytes "$n")"
    else
      printf '  %-44s unknown\n' "$(model_set_title "$set")"
    fi
  done
  printf '  %-44s %s\n' Total "$(format_bytes "$total")"
  printf 'Profile: %s\n' "$(profile_installed && echo installed || echo not-installed)"
}

print_features() {
  local f
  for f in "${FEATURES[@]}"; do printf '%-28s %s\n' "$f" "$(feature_title "$f")"; done
}

open_profile_settings() {
  open 'x-apple.systempreferences:com.apple.Profiles-Settings.extension' 2>/dev/null || open 'x-apple.systempreferences:com.apple.preferences.configurationprofiles' 2>/dev/null || true
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
  printf 'Turn off Apple Intelligence and reset the selected models? [y/N] '
  read -r answer
  [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

off_command() {
  parse_args "$@"
  build_helper
  legacy_profile_installed && fail "legacy RemoveMacAI profile is installed; run '$0 revert' first"
  validate_uaf_catalog
  local sets
  sets="$(sets_to_remove)"

  printf 'Features to disable:\n'
  local f
  for f in "${FEATURES[@]}"; do kept "$f" || printf '  - %s\n' "$(feature_title "$f")"; done
  printf 'Model sets to reset:\n%s\n' "$(printf '%s\n' "$sets" | sed 's/^/  - /')"

  if (( DRY_RUN == 1 )); then
    local dry="${TMPDIR:-/tmp}/Apple-AI-remover.$$.mobileconfig"
    build_profile "$dry" "$sets"
    info 'DRY RUN: no profile was installed and no model was reset.'
    info "generated profile: $dry"
    return 0
  fi

  confirm || { info 'Nothing changed.'; return 0; }

  local expected
  expected="$(keep_csv)"
  build_profile "$PROFILE_FILE" "$sets"
  open "$PROFILE_FILE" 2>/dev/null || true
  open_profile_settings
  info "Approve '$PROFILE_NAME' in System Settings."
  wait_for_profile "$expected" || fail 'profile installation was not observed; no model reset was attempted'

  if [[ -n "$sets" ]]; then
    if reset_models "$sets"; then
      info 'All selected model sets reset successfully.'
    else
      fail 'profile is installed, but one or more model resets failed; run status to inspect remaining model state'
    fi
  fi
  info "Done. Run: $0 status"
}

revert_command() {
  build_helper
  local current=0 legacy=0
  profile_installed && current=1
  legacy_profile_installed && legacy=1
  if (( current == 0 && legacy == 0 )); then info 'No Apple AI remover profile is installed.'; return 0; fi
  if (( YES == 0 )); then
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
  local f set x saved_keep all a b
  for f in "${FEATURES[@]}"; do
    feature_title "$f" >/dev/null || fail "missing title for $f"
    while IFS= read -r x; do
      [[ -z "$x" ]] && continue
      model_set_asset_type "$x" >/dev/null || fail "unknown model set $x referenced by $f"
    done < <(feature_model_sets "$f")
  done
  for set in "${MODEL_SETS[@]}"; do model_set_asset_type "$set" >/dev/null || fail "missing model-set mapping $set"; done

  saved_keep=("${KEEP[@]}")
  KEEP=()
  all="$(sets_to_remove)"
  [[ "$(printf '%s\n' "$all" | sort)" == "$(printf '%s\n' "${MODEL_SETS[@]}" | sort)" ]] || fail 'empty keep set must remove every model set'

  KEEP=(writing-tools)
  all="$(sets_to_remove)"
  ! grep -qx 'com.apple.modelcatalog' <<< "$all" || fail 'writing-tools must protect foundation models'
  grep -qx 'com.apple.MobileAsset.UAF.FM.Visual' <<< "$all" || fail 'writing-tools unexpectedly protects visual models'
  KEEP=("${saved_keep[@]}")

  a="$(stable_uuid "$PROFILE_ID")"; b="$(stable_uuid "$PROFILE_ID")"; [[ "$a" == "$b" ]] || fail 'payload UUID generator is not stable'
  printf 'selftest: PASS (%s features, %s model sets)\n' "${#FEATURES[@]}" "${#MODEL_SETS[@]}"
}

usage() {
  cat <<EOF_USAGE
$PRODUCT_NAME $VERSION

Usage:
  $0 status
  $0 features
  $0 off [--keep feature[,feature...]] [--dry-run] [--yes]
  $0 revert [--yes]
  $0 selftest

The mutating commands target macOS $TARGET_MAJOR.x on Apple silicon.
EOF_USAGE
}

main() {
  local command="${1:-status}"
  shift || true
  case "$command" in
    status) require_platform; status_command "$@" ;;
    features) [[ "$#" -eq 0 ]] || fail 'features takes no options'; print_features ;;
    off) require_platform; off_command "$@" ;;
    revert) require_platform; parse_args "$@"; revert_command ;;
    selftest) [[ "$#" -eq 0 ]] || fail 'selftest takes no options'; selftest_command ;;
    --help|-h|help) usage ;;
    --version|-v|version) echo "$VERSION" ;;
    *) usage >&2; exit 1 ;;
  esac
}

main "$@"
\t'"${key}"
    [[ -n "$set" ]] || continue
    key="DownloadServerBaseURLOverride-$(model_set_asset_type "$set")"
    PREF_LINES="${PREF_LINES}com.apple.MobileAsset"$'\t'"${key}"$'\t'"${BLOCKED_URL}"$'\n'
  done <<< "$sets"

  mkdir -p "$(dirname "$output")"
  {
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
    printf '%s\n' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    printf '%s\n' '<plist version="1.0"><dict>'
    printf '%s\n' '<key>PayloadType</key><string>Configuration</string>'
    printf '%s\n' '<key>PayloadVersion</key><integer>1</integer>'
    printf '<key>PayloadIdentifier</key><string>%s</string>\n' "$PROFILE_ID"
    printf '<key>PayloadUUID</key><string>%s</string>\n' "$(stable_uuid "$PROFILE_ID")"
    printf '<key>PayloadDisplayName</key><string>%s</string>\n' "$(xml_escape "$PROFILE_NAME")"
    printf '%s\n' '<key>PayloadDescription</key><string>Disables Apple Intelligence features and prevents selected model sets from being re-downloaded. Remove this profile to undo.</string>'
    printf '%s\n' '<key>PayloadOrganization</key><string>Apple AI remover</string>'
    printf '%s\n' '<key>PayloadScope</key><string>System</string>'
    printf '%s\n' '<key>PayloadRemovalDisallowed</key><false/>'
    printf '%s\n' '<key>PayloadContent</key><array>'

    payload_header com.apple.applicationaccess restrictions 'Apple Intelligence restrictions'
    printf '%s\n' '      <key>PayloadContent</key><dict>'
    for feature in "${FEATURES[@]}"; do
      kept "$feature" && continue
      while IFS= read -r key; do
        [[ -n "$key" ]] && printf '        <key>%s</key><false/>\n' "$(xml_escape "$key")"
      done < <(feature_restrictions "$feature")
    done
    printf '%s\n' '      </dict>' '    </dict>'

    for d in com.apple.assistant.support com.apple.Siri group.com.apple.mail group.com.apple.usernoted com.apple.MobileSMS .GlobalPreferences com.apple.spatialphotosrelive; do
      PREF_LINES=''
      while IFS=$'\t' read -r domain key value; do
        [[ "$domain" == "$d" ]] || continue
        PREF_LINES="${PREF_LINES}${key}"$'\t'"${value}"$'\n'
      done <<< "$ALL_PREFS"
      append_pref_payload "$d" "$d" "Forced settings: $d"
    done

    PREF_LINES=''
    while IFS=$'\t' read -r domain key value; do
      [[ "$domain" == 'com.apple.MobileAsset' ]] || continue
      PREF_LINES="${PREF_LINES}${key}"$'\t'"${value}"$'\n'
    done <<< "$ALL_PREFS"
    append_pref_payload com.apple.MobileAsset MobileAsset 'MobileAsset download overrides'

    PREF_LINES="installed"$'\t'true$'\n'"kept"$'\t'"$(keep_csv)"$'\n'
    append_pref_payload "$PROFILE_ID" marker 'Apple AI remover state'

    printf '%s\n' '</array></dict></plist>'
  } > "$tmp"
  /usr/bin/plutil -lint "$tmp" >/dev/null 2>&1 || { rm -f "$tmp"; fail 'generated profile failed plist validation'; }
  mv "$tmp" "$output"
}

keep_csv() {
  local out='' item
  for item in "${KEEP[@]}"; do
    [[ -n "$out" ]] && out="$out,"
    out="$out$item"
  done
  printf '%s' "$out"
}

helper_pref() { "$HELPER" pref "$1" "$2"; }
profile_installed() { local o; o="$(helper_pref "$PROFILE_ID" installed 2>/dev/null)" || return 1; [[ "$o" == *$'forced=1\tvalue=true'* ]]; }
legacy_profile_installed() { local o; o="$(helper_pref "$LEGACY_PROFILE_ID" installed 2>/dev/null)" || return 1; [[ "$o" == *$'forced=1\tvalue=true'* ]]; }
profile_kept_csv() { local o; o="$(helper_pref "$PROFILE_ID" kept 2>/dev/null)" || return 1; printf '%s' "${o#*value=}"; }

validate_uaf_catalog() {
  local set expected actual
  for set in "${MODEL_SETS[@]}"; do
    expected="$(model_set_asset_type "$set")"
    actual="$($HELPER asset-type "$set")" || fail "UAF asset-set lookup failed for $set"
    [[ "$actual" == "$expected" ]] || fail "UAF mapping mismatch for $set: expected $expected, got $actual"
  done
}

model_bytes() {
  local set="$1" out
  out="$($HELPER bytes "$set" 2>/dev/null)" || return 1
  [[ "$out" =~ ^[0-9]+$ ]] || return 1
  printf '%s' "$out"
}

format_bytes() {
  local b="$1"
  if (( b >= 1000000000 )); then awk -v n="$b" 'BEGIN { printf "%.1f GB", n/1e9 }'
  elif (( b > 0 )); then awk -v n="$b" 'BEGIN { printf "%.0f MB", n/1e6 }'
  else echo '0 MB'; fi
}

feature_state() {
  local feature="$1" domain key want output forced value
  local all=1 any=0
  while IFS=$'\t' read -r domain key want; do
    [[ -n "$domain" ]] || continue
    output="$(helper_pref "$domain" "$key" 2>/dev/null)" || { echo unknown; return; }
    forced="$(printf '%s' "$output" | sed -n 's/.*forced=\([^\t]*\).*/\1/p')"
    value="$(printf '%s' "$output" | sed -n 's/.*value=\([^\t]*\)$/\1/p')"
    [[ "$forced" == 1 && "$value" == "$want" ]] && any=1 || all=0
  done < <(feature_preferences "$feature")
  if (( all == 1 && any == 1 )); then echo locked; return; fi

  case "$feature" in
    chatgpt|writing-tools|genmoji|image-playground|safari-summaries|notes-summaries)
      local restricted_ok=1 r
      while IFS= read -r r; do
        [[ -n "$r" ]] || continue
        output="$(helper_pref com.apple.applicationaccess "$r" 2>/dev/null)" || { echo unknown; return; }
        [[ "$output" == *$'forced=1\tvalue=false'* ]] || restricted_ok=0
      done < <(feature_restrictions "$feature")
      (( restricted_ok == 1 )) && echo locked && return
      ;;
  esac

  if profile_installed && ! kept "$feature" && [[ -z "$(feature_preferences "$feature")" ]] && [[ -z "$(feature_restrictions "$feature")" ]]; then
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
  local feature state set n total=0
  for feature in "${FEATURES[@]}"; do
    state="$(feature_state "$feature")"
    printf '%-44s %s\n' "$(feature_title "$feature")" "$state"
  done
  printf '\nModels on disk\n'
  for set in "${MODEL_SETS[@]}"; do
    if n="$(model_bytes "$set")"; then
      total=$((total+n)); printf '  %-44s %s\n' "$(model_set_title "$set")" "$(format_bytes "$n")"
    else
      printf '  %-44s unknown\n' "$(model_set_title "$set")"
    fi
  done
  printf '  %-44s %s\n' Total "$(format_bytes "$total")"
  printf 'Profile: %s\n' "$(profile_installed && echo installed || echo not-installed)"
}

print_features() {
  local f
  for f in "${FEATURES[@]}"; do printf '%-28s %s\n' "$f" "$(feature_title "$f")"; done
}

open_profile_settings() {
  open 'x-apple.systempreferences:com.apple.Profiles-Settings.extension' 2>/dev/null || open 'x-apple.systempreferences:com.apple.preferences.configurationprofiles' 2>/dev/null || true
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
  printf 'Turn off Apple Intelligence and reset the selected models? [y/N] '
  read -r answer
  [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

off_command() {
  parse_args "$@"
  build_helper
  legacy_profile_installed && fail "legacy RemoveMacAI profile is installed; run '$0 revert' first"
  validate_uaf_catalog
  local sets
  sets="$(sets_to_remove)"

  printf 'Features to disable:\n'
  local f
  for f in "${FEATURES[@]}"; do kept "$f" || printf '  - %s\n' "$(feature_title "$f")"; done
  printf 'Model sets to reset:\n%s\n' "$(printf '%s\n' "$sets" | sed 's/^/  - /')"

  if (( DRY_RUN == 1 )); then
    local dry="${TMPDIR:-/tmp}/Apple-AI-remover.$$.mobileconfig"
    build_profile "$dry" "$sets"
    info 'DRY RUN: no profile was installed and no model was reset.'
    info "generated profile: $dry"
    return 0
  fi

  confirm || { info 'Nothing changed.'; return 0; }

  local expected
  expected="$(keep_csv)"
  build_profile "$PROFILE_FILE" "$sets"
  open "$PROFILE_FILE" 2>/dev/null || true
  open_profile_settings
  info "Approve '$PROFILE_NAME' in System Settings."
  wait_for_profile "$expected" || fail 'profile installation was not observed; no model reset was attempted'

  if [[ -n "$sets" ]]; then
    if reset_models "$sets"; then
      info 'All selected model sets reset successfully.'
    else
      fail 'profile is installed, but one or more model resets failed; run status to inspect remaining model state'
    fi
  fi
  info "Done. Run: $0 status"
}

revert_command() {
  build_helper
  local current=0 legacy=0
  profile_installed && current=1
  legacy_profile_installed && legacy=1
  if (( current == 0 && legacy == 0 )); then info 'No Apple AI remover profile is installed.'; return 0; fi
  if (( YES == 0 )); then
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
  local f set x saved_keep all a b
  for f in "${FEATURES[@]}"; do
    feature_title "$f" >/dev/null || fail "missing title for $f"
    while IFS= read -r x; do
      [[ -z "$x" ]] && continue
      model_set_asset_type "$x" >/dev/null || fail "unknown model set $x referenced by $f"
    done < <(feature_model_sets "$f")
  done
  for set in "${MODEL_SETS[@]}"; do model_set_asset_type "$set" >/dev/null || fail "missing model-set mapping $set"; done

  saved_keep=("${KEEP[@]}")
  KEEP=()
  all="$(sets_to_remove)"
  [[ "$(printf '%s\n' "$all" | sort)" == "$(printf '%s\n' "${MODEL_SETS[@]}" | sort)" ]] || fail 'empty keep set must remove every model set'

  KEEP=(writing-tools)
  all="$(sets_to_remove)"
  ! grep -qx 'com.apple.modelcatalog' <<< "$all" || fail 'writing-tools must protect foundation models'
  grep -qx 'com.apple.MobileAsset.UAF.FM.Visual' <<< "$all" || fail 'writing-tools unexpectedly protects visual models'
  KEEP=("${saved_keep[@]}")

  a="$(stable_uuid "$PROFILE_ID")"; b="$(stable_uuid "$PROFILE_ID")"; [[ "$a" == "$b" ]] || fail 'payload UUID generator is not stable'
  printf 'selftest: PASS (%s features, %s model sets)\n' "${#FEATURES[@]}" "${#MODEL_SETS[@]}"
}

usage() {
  cat <<EOF_USAGE
$PRODUCT_NAME $VERSION

Usage:
  $0 status
  $0 features
  $0 off [--keep feature[,feature...]] [--dry-run] [--yes]
  $0 revert [--yes]
  $0 selftest

The mutating commands target macOS $TARGET_MAJOR.x on Apple silicon.
EOF_USAGE
}

main() {
  local command="${1:-status}"
  shift || true
  case "$command" in
    status) require_platform; status_command "$@" ;;
    features) [[ "$#" -eq 0 ]] || fail 'features takes no options'; print_features ;;
    off) require_platform; off_command "$@" ;;
    revert) require_platform; parse_args "$@"; revert_command ;;
    selftest) [[ "$#" -eq 0 ]] || fail 'selftest takes no options'; selftest_command ;;
    --help|-h|help) usage ;;
    --version|-v|version) echo "$VERSION" ;;
    *) usage >&2; exit 1 ;;
  esac
}

main "$@"
\t'"${value}"
    [[ -n "$set" ]] || continue
    key="DownloadServerBaseURLOverride-$(model_set_asset_type "$set")"
    PREF_LINES="${PREF_LINES}com.apple.MobileAsset"$'\t'"${key}"$'\t'"${BLOCKED_URL}"$'\n'
  done <<< "$sets"

  mkdir -p "$(dirname "$output")"
  {
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
    printf '%s\n' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    printf '%s\n' '<plist version="1.0"><dict>'
    printf '%s\n' '<key>PayloadType</key><string>Configuration</string>'
    printf '%s\n' '<key>PayloadVersion</key><integer>1</integer>'
    printf '<key>PayloadIdentifier</key><string>%s</string>\n' "$PROFILE_ID"
    printf '<key>PayloadUUID</key><string>%s</string>\n' "$(stable_uuid "$PROFILE_ID")"
    printf '<key>PayloadDisplayName</key><string>%s</string>\n' "$(xml_escape "$PROFILE_NAME")"
    printf '%s\n' '<key>PayloadDescription</key><string>Disables Apple Intelligence features and prevents selected model sets from being re-downloaded. Remove this profile to undo.</string>'
    printf '%s\n' '<key>PayloadOrganization</key><string>Apple AI remover</string>'
    printf '%s\n' '<key>PayloadScope</key><string>System</string>'
    printf '%s\n' '<key>PayloadRemovalDisallowed</key><false/>'
    printf '%s\n' '<key>PayloadContent</key><array>'

    payload_header com.apple.applicationaccess restrictions 'Apple Intelligence restrictions'
    printf '%s\n' '      <key>PayloadContent</key><dict>'
    for feature in "${FEATURES[@]}"; do
      kept "$feature" && continue
      while IFS= read -r key; do
        [[ -n "$key" ]] && printf '        <key>%s</key><false/>\n' "$(xml_escape "$key")"
      done < <(feature_restrictions "$feature")
    done
    printf '%s\n' '      </dict>' '    </dict>'

    for d in com.apple.assistant.support com.apple.Siri group.com.apple.mail group.com.apple.usernoted com.apple.MobileSMS .GlobalPreferences com.apple.spatialphotosrelive; do
      PREF_LINES=''
      while IFS=$'\t' read -r domain key value; do
        [[ "$domain" == "$d" ]] || continue
        PREF_LINES="${PREF_LINES}${key}"$'\t'"${value}"$'\n'
      done <<< "$ALL_PREFS"
      append_pref_payload "$d" "$d" "Forced settings: $d"
    done

    PREF_LINES=''
    while IFS=$'\t' read -r domain key value; do
      [[ "$domain" == 'com.apple.MobileAsset' ]] || continue
      PREF_LINES="${PREF_LINES}${key}"$'\t'"${value}"$'\n'
    done <<< "$ALL_PREFS"
    append_pref_payload com.apple.MobileAsset MobileAsset 'MobileAsset download overrides'

    PREF_LINES="installed"$'\t'true$'\n'"kept"$'\t'"$(keep_csv)"$'\n'
    append_pref_payload "$PROFILE_ID" marker 'Apple AI remover state'

    printf '%s\n' '</array></dict></plist>'
  } > "$tmp"
  /usr/bin/plutil -lint "$tmp" >/dev/null 2>&1 || { rm -f "$tmp"; fail 'generated profile failed plist validation'; }
  mv "$tmp" "$output"
}

keep_csv() {
  local out='' item
  for item in "${KEEP[@]}"; do
    [[ -n "$out" ]] && out="$out,"
    out="$out$item"
  done
  printf '%s' "$out"
}

helper_pref() { "$HELPER" pref "$1" "$2"; }
profile_installed() { local o; o="$(helper_pref "$PROFILE_ID" installed 2>/dev/null)" || return 1; [[ "$o" == *$'forced=1\tvalue=true'* ]]; }
legacy_profile_installed() { local o; o="$(helper_pref "$LEGACY_PROFILE_ID" installed 2>/dev/null)" || return 1; [[ "$o" == *$'forced=1\tvalue=true'* ]]; }
profile_kept_csv() { local o; o="$(helper_pref "$PROFILE_ID" kept 2>/dev/null)" || return 1; printf '%s' "${o#*value=}"; }

validate_uaf_catalog() {
  local set expected actual
  for set in "${MODEL_SETS[@]}"; do
    expected="$(model_set_asset_type "$set")"
    actual="$($HELPER asset-type "$set")" || fail "UAF asset-set lookup failed for $set"
    [[ "$actual" == "$expected" ]] || fail "UAF mapping mismatch for $set: expected $expected, got $actual"
  done
}

model_bytes() {
  local set="$1" out
  out="$($HELPER bytes "$set" 2>/dev/null)" || return 1
  [[ "$out" =~ ^[0-9]+$ ]] || return 1
  printf '%s' "$out"
}

format_bytes() {
  local b="$1"
  if (( b >= 1000000000 )); then awk -v n="$b" 'BEGIN { printf "%.1f GB", n/1e9 }'
  elif (( b > 0 )); then awk -v n="$b" 'BEGIN { printf "%.0f MB", n/1e6 }'
  else echo '0 MB'; fi
}

feature_state() {
  local feature="$1" domain key want output forced value
  local all=1 any=0
  while IFS=$'\t' read -r domain key want; do
    [[ -n "$domain" ]] || continue
    output="$(helper_pref "$domain" "$key" 2>/dev/null)" || { echo unknown; return; }
    forced="$(printf '%s' "$output" | sed -n 's/.*forced=\([^\t]*\).*/\1/p')"
    value="$(printf '%s' "$output" | sed -n 's/.*value=\([^\t]*\)$/\1/p')"
    [[ "$forced" == 1 && "$value" == "$want" ]] && any=1 || all=0
  done < <(feature_preferences "$feature")
  if (( all == 1 && any == 1 )); then echo locked; return; fi

  case "$feature" in
    chatgpt|writing-tools|genmoji|image-playground|safari-summaries|notes-summaries)
      local restricted_ok=1 r
      while IFS= read -r r; do
        [[ -n "$r" ]] || continue
        output="$(helper_pref com.apple.applicationaccess "$r" 2>/dev/null)" || { echo unknown; return; }
        [[ "$output" == *$'forced=1\tvalue=false'* ]] || restricted_ok=0
      done < <(feature_restrictions "$feature")
      (( restricted_ok == 1 )) && echo locked && return
      ;;
  esac

  if profile_installed && ! kept "$feature" && [[ -z "$(feature_preferences "$feature")" ]] && [[ -z "$(feature_restrictions "$feature")" ]]; then
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
  local feature state set n total=0
  for feature in "${FEATURES[@]}"; do
    state="$(feature_state "$feature")"
    printf '%-44s %s\n' "$(feature_title "$feature")" "$state"
  done
  printf '\nModels on disk\n'
  for set in "${MODEL_SETS[@]}"; do
    if n="$(model_bytes "$set")"; then
      total=$((total+n)); printf '  %-44s %s\n' "$(model_set_title "$set")" "$(format_bytes "$n")"
    else
      printf '  %-44s unknown\n' "$(model_set_title "$set")"
    fi
  done
  printf '  %-44s %s\n' Total "$(format_bytes "$total")"
  printf 'Profile: %s\n' "$(profile_installed && echo installed || echo not-installed)"
}

print_features() {
  local f
  for f in "${FEATURES[@]}"; do printf '%-28s %s\n' "$f" "$(feature_title "$f")"; done
}

open_profile_settings() {
  open 'x-apple.systempreferences:com.apple.Profiles-Settings.extension' 2>/dev/null || open 'x-apple.systempreferences:com.apple.preferences.configurationprofiles' 2>/dev/null || true
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
  printf 'Turn off Apple Intelligence and reset the selected models? [y/N] '
  read -r answer
  [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

off_command() {
  parse_args "$@"
  build_helper
  legacy_profile_installed && fail "legacy RemoveMacAI profile is installed; run '$0 revert' first"
  validate_uaf_catalog
  local sets
  sets="$(sets_to_remove)"

  printf 'Features to disable:\n'
  local f
  for f in "${FEATURES[@]}"; do kept "$f" || printf '  - %s\n' "$(feature_title "$f")"; done
  printf 'Model sets to reset:\n%s\n' "$(printf '%s\n' "$sets" | sed 's/^/  - /')"

  if (( DRY_RUN == 1 )); then
    local dry="${TMPDIR:-/tmp}/Apple-AI-remover.$$.mobileconfig"
    build_profile "$dry" "$sets"
    info 'DRY RUN: no profile was installed and no model was reset.'
    info "generated profile: $dry"
    return 0
  fi

  confirm || { info 'Nothing changed.'; return 0; }

  local expected
  expected="$(keep_csv)"
  build_profile "$PROFILE_FILE" "$sets"
  open "$PROFILE_FILE" 2>/dev/null || true
  open_profile_settings
  info "Approve '$PROFILE_NAME' in System Settings."
  wait_for_profile "$expected" || fail 'profile installation was not observed; no model reset was attempted'

  if [[ -n "$sets" ]]; then
    if reset_models "$sets"; then
      info 'All selected model sets reset successfully.'
    else
      fail 'profile is installed, but one or more model resets failed; run status to inspect remaining model state'
    fi
  fi
  info "Done. Run: $0 status"
}

revert_command() {
  build_helper
  local current=0 legacy=0
  profile_installed && current=1
  legacy_profile_installed && legacy=1
  if (( current == 0 && legacy == 0 )); then info 'No Apple AI remover profile is installed.'; return 0; fi
  if (( YES == 0 )); then
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
  local f set x saved_keep all a b
  for f in "${FEATURES[@]}"; do
    feature_title "$f" >/dev/null || fail "missing title for $f"
    while IFS= read -r x; do
      [[ -z "$x" ]] && continue
      model_set_asset_type "$x" >/dev/null || fail "unknown model set $x referenced by $f"
    done < <(feature_model_sets "$f")
  done
  for set in "${MODEL_SETS[@]}"; do model_set_asset_type "$set" >/dev/null || fail "missing model-set mapping $set"; done

  saved_keep=("${KEEP[@]}")
  KEEP=()
  all="$(sets_to_remove)"
  [[ "$(printf '%s\n' "$all" | sort)" == "$(printf '%s\n' "${MODEL_SETS[@]}" | sort)" ]] || fail 'empty keep set must remove every model set'

  KEEP=(writing-tools)
  all="$(sets_to_remove)"
  ! grep -qx 'com.apple.modelcatalog' <<< "$all" || fail 'writing-tools must protect foundation models'
  grep -qx 'com.apple.MobileAsset.UAF.FM.Visual' <<< "$all" || fail 'writing-tools unexpectedly protects visual models'
  KEEP=("${saved_keep[@]}")

  a="$(stable_uuid "$PROFILE_ID")"; b="$(stable_uuid "$PROFILE_ID")"; [[ "$a" == "$b" ]] || fail 'payload UUID generator is not stable'
  printf 'selftest: PASS (%s features, %s model sets)\n' "${#FEATURES[@]}" "${#MODEL_SETS[@]}"
}

usage() {
  cat <<EOF_USAGE
$PRODUCT_NAME $VERSION

Usage:
  $0 status
  $0 features
  $0 off [--keep feature[,feature...]] [--dry-run] [--yes]
  $0 revert [--yes]
  $0 selftest

The mutating commands target macOS $TARGET_MAJOR.x on Apple silicon.
EOF_USAGE
}

main() {
  local command="${1:-status}"
  shift || true
  case "$command" in
    status) require_platform; status_command "$@" ;;
    features) [[ "$#" -eq 0 ]] || fail 'features takes no options'; print_features ;;
    off) require_platform; off_command "$@" ;;
    revert) require_platform; parse_args "$@"; revert_command ;;
    selftest) [[ "$#" -eq 0 ]] || fail 'selftest takes no options'; selftest_command ;;
    --help|-h|help) usage ;;
    --version|-v|version) echo "$VERSION" ;;
    *) usage >&2; exit 1 ;;
  esac
}

main "$@"
\n'
    done < <(feature_preferences "$feature")
  done
  while IFS= read -r set; do
    [[ -n "$set" ]] || continue
    key="DownloadServerBaseURLOverride-$(model_set_asset_type "$set")"
    PREF_LINES="${PREF_LINES}com.apple.MobileAsset"$'\t'"${key}"$'\t'"${BLOCKED_URL}"$'\n'
  done <<< "$sets"

  mkdir -p "$(dirname "$output")"
  {
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
    printf '%s\n' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    printf '%s\n' '<plist version="1.0"><dict>'
    printf '%s\n' '<key>PayloadType</key><string>Configuration</string>'
    printf '%s\n' '<key>PayloadVersion</key><integer>1</integer>'
    printf '<key>PayloadIdentifier</key><string>%s</string>\n' "$PROFILE_ID"
    printf '<key>PayloadUUID</key><string>%s</string>\n' "$(stable_uuid "$PROFILE_ID")"
    printf '<key>PayloadDisplayName</key><string>%s</string>\n' "$(xml_escape "$PROFILE_NAME")"
    printf '%s\n' '<key>PayloadDescription</key><string>Disables Apple Intelligence features and prevents selected model sets from being re-downloaded. Remove this profile to undo.</string>'
    printf '%s\n' '<key>PayloadOrganization</key><string>Apple AI remover</string>'
    printf '%s\n' '<key>PayloadScope</key><string>System</string>'
    printf '%s\n' '<key>PayloadRemovalDisallowed</key><false/>'
    printf '%s\n' '<key>PayloadContent</key><array>'

    payload_header com.apple.applicationaccess restrictions 'Apple Intelligence restrictions'
    printf '%s\n' '      <key>PayloadContent</key><dict>'
    for feature in "${FEATURES[@]}"; do
      kept "$feature" && continue
      while IFS= read -r key; do
        [[ -n "$key" ]] && printf '        <key>%s</key><false/>\n' "$(xml_escape "$key")"
      done < <(feature_restrictions "$feature")
    done
    printf '%s\n' '      </dict>' '    </dict>'

    for d in com.apple.assistant.support com.apple.Siri group.com.apple.mail group.com.apple.usernoted com.apple.MobileSMS .GlobalPreferences com.apple.spatialphotosrelive; do
      PREF_LINES=''
      while IFS=$'\t' read -r domain key value; do
        [[ "$domain" == "$d" ]] || continue
        PREF_LINES="${PREF_LINES}${key}"$'\t'"${value}"$'\n'
      done <<< "$ALL_PREFS"
      append_pref_payload "$d" "$d" "Forced settings: $d"
    done

    PREF_LINES=''
    while IFS=$'\t' read -r domain key value; do
      [[ "$domain" == 'com.apple.MobileAsset' ]] || continue
      PREF_LINES="${PREF_LINES}${key}"$'\t'"${value}"$'\n'
    done <<< "$ALL_PREFS"
    append_pref_payload com.apple.MobileAsset MobileAsset 'MobileAsset download overrides'

    PREF_LINES="installed"$'\t'true$'\n'"kept"$'\t'"$(keep_csv)"$'\n'
    append_pref_payload "$PROFILE_ID" marker 'Apple AI remover state'

    printf '%s\n' '</array></dict></plist>'
  } > "$tmp"
  /usr/bin/plutil -lint "$tmp" >/dev/null 2>&1 || { rm -f "$tmp"; fail 'generated profile failed plist validation'; }
  mv "$tmp" "$output"
}

keep_csv() {
  local out='' item
  for item in "${KEEP[@]}"; do
    [[ -n "$out" ]] && out="$out,"
    out="$out$item"
  done
  printf '%s' "$out"
}

helper_pref() { "$HELPER" pref "$1" "$2"; }
profile_installed() { local o; o="$(helper_pref "$PROFILE_ID" installed 2>/dev/null)" || return 1; [[ "$o" == *$'forced=1\tvalue=true'* ]]; }
legacy_profile_installed() { local o; o="$(helper_pref "$LEGACY_PROFILE_ID" installed 2>/dev/null)" || return 1; [[ "$o" == *$'forced=1\tvalue=true'* ]]; }
profile_kept_csv() { local o; o="$(helper_pref "$PROFILE_ID" kept 2>/dev/null)" || return 1; printf '%s' "${o#*value=}"; }

validate_uaf_catalog() {
  local set expected actual
  for set in "${MODEL_SETS[@]}"; do
    expected="$(model_set_asset_type "$set")"
    actual="$($HELPER asset-type "$set")" || fail "UAF asset-set lookup failed for $set"
    [[ "$actual" == "$expected" ]] || fail "UAF mapping mismatch for $set: expected $expected, got $actual"
  done
}

model_bytes() {
  local set="$1" out
  out="$($HELPER bytes "$set" 2>/dev/null)" || return 1
  [[ "$out" =~ ^[0-9]+$ ]] || return 1
  printf '%s' "$out"
}

format_bytes() {
  local b="$1"
  if (( b >= 1000000000 )); then awk -v n="$b" 'BEGIN { printf "%.1f GB", n/1e9 }'
  elif (( b > 0 )); then awk -v n="$b" 'BEGIN { printf "%.0f MB", n/1e6 }'
  else echo '0 MB'; fi
}

feature_state() {
  local feature="$1" domain key want output forced value
  local all=1 any=0
  while IFS=$'\t' read -r domain key want; do
    [[ -n "$domain" ]] || continue
    output="$(helper_pref "$domain" "$key" 2>/dev/null)" || { echo unknown; return; }
    forced="$(printf '%s' "$output" | sed -n 's/.*forced=\([^\t]*\).*/\1/p')"
    value="$(printf '%s' "$output" | sed -n 's/.*value=\([^\t]*\)$/\1/p')"
    [[ "$forced" == 1 && "$value" == "$want" ]] && any=1 || all=0
  done < <(feature_preferences "$feature")
  if (( all == 1 && any == 1 )); then echo locked; return; fi

  case "$feature" in
    chatgpt|writing-tools|genmoji|image-playground|safari-summaries|notes-summaries)
      local restricted_ok=1 r
      while IFS= read -r r; do
        [[ -n "$r" ]] || continue
        output="$(helper_pref com.apple.applicationaccess "$r" 2>/dev/null)" || { echo unknown; return; }
        [[ "$output" == *$'forced=1\tvalue=false'* ]] || restricted_ok=0
      done < <(feature_restrictions "$feature")
      (( restricted_ok == 1 )) && echo locked && return
      ;;
  esac

  if profile_installed && ! kept "$feature" && [[ -z "$(feature_preferences "$feature")" ]] && [[ -z "$(feature_restrictions "$feature")" ]]; then
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
  local feature state set n total=0
  for feature in "${FEATURES[@]}"; do
    state="$(feature_state "$feature")"
    printf '%-44s %s\n' "$(feature_title "$feature")" "$state"
  done
  printf '\nModels on disk\n'
  for set in "${MODEL_SETS[@]}"; do
    if n="$(model_bytes "$set")"; then
      total=$((total+n)); printf '  %-44s %s\n' "$(model_set_title "$set")" "$(format_bytes "$n")"
    else
      printf '  %-44s unknown\n' "$(model_set_title "$set")"
    fi
  done
  printf '  %-44s %s\n' Total "$(format_bytes "$total")"
  printf 'Profile: %s\n' "$(profile_installed && echo installed || echo not-installed)"
}

print_features() {
  local f
  for f in "${FEATURES[@]}"; do printf '%-28s %s\n' "$f" "$(feature_title "$f")"; done
}

open_profile_settings() {
  open 'x-apple.systempreferences:com.apple.Profiles-Settings.extension' 2>/dev/null || open 'x-apple.systempreferences:com.apple.preferences.configurationprofiles' 2>/dev/null || true
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
  printf 'Turn off Apple Intelligence and reset the selected models? [y/N] '
  read -r answer
  [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

off_command() {
  parse_args "$@"
  build_helper
  legacy_profile_installed && fail "legacy RemoveMacAI profile is installed; run '$0 revert' first"
  validate_uaf_catalog
  local sets
  sets="$(sets_to_remove)"

  printf 'Features to disable:\n'
  local f
  for f in "${FEATURES[@]}"; do kept "$f" || printf '  - %s\n' "$(feature_title "$f")"; done
  printf 'Model sets to reset:\n%s\n' "$(printf '%s\n' "$sets" | sed 's/^/  - /')"

  if (( DRY_RUN == 1 )); then
    local dry="${TMPDIR:-/tmp}/Apple-AI-remover.$$.mobileconfig"
    build_profile "$dry" "$sets"
    info 'DRY RUN: no profile was installed and no model was reset.'
    info "generated profile: $dry"
    return 0
  fi

  confirm || { info 'Nothing changed.'; return 0; }

  local expected
  expected="$(keep_csv)"
  build_profile "$PROFILE_FILE" "$sets"
  open "$PROFILE_FILE" 2>/dev/null || true
  open_profile_settings
  info "Approve '$PROFILE_NAME' in System Settings."
  wait_for_profile "$expected" || fail 'profile installation was not observed; no model reset was attempted'

  if [[ -n "$sets" ]]; then
    if reset_models "$sets"; then
      info 'All selected model sets reset successfully.'
    else
      fail 'profile is installed, but one or more model resets failed; run status to inspect remaining model state'
    fi
  fi
  info "Done. Run: $0 status"
}

revert_command() {
  build_helper
  local current=0 legacy=0
  profile_installed && current=1
  legacy_profile_installed && legacy=1
  if (( current == 0 && legacy == 0 )); then info 'No Apple AI remover profile is installed.'; return 0; fi
  if (( YES == 0 )); then
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
  local f set x saved_keep all a b
  for f in "${FEATURES[@]}"; do
    feature_title "$f" >/dev/null || fail "missing title for $f"
    while IFS= read -r x; do
      [[ -z "$x" ]] && continue
      model_set_asset_type "$x" >/dev/null || fail "unknown model set $x referenced by $f"
    done < <(feature_model_sets "$f")
  done
  for set in "${MODEL_SETS[@]}"; do model_set_asset_type "$set" >/dev/null || fail "missing model-set mapping $set"; done

  saved_keep=("${KEEP[@]}")
  KEEP=()
  all="$(sets_to_remove)"
  [[ "$(printf '%s\n' "$all" | sort)" == "$(printf '%s\n' "${MODEL_SETS[@]}" | sort)" ]] || fail 'empty keep set must remove every model set'

  KEEP=(writing-tools)
  all="$(sets_to_remove)"
  ! grep -qx 'com.apple.modelcatalog' <<< "$all" || fail 'writing-tools must protect foundation models'
  grep -qx 'com.apple.MobileAsset.UAF.FM.Visual' <<< "$all" || fail 'writing-tools unexpectedly protects visual models'
  KEEP=("${saved_keep[@]}")

  a="$(stable_uuid "$PROFILE_ID")"; b="$(stable_uuid "$PROFILE_ID")"; [[ "$a" == "$b" ]] || fail 'payload UUID generator is not stable'
  printf 'selftest: PASS (%s features, %s model sets)\n' "${#FEATURES[@]}" "${#MODEL_SETS[@]}"
}

usage() {
  cat <<EOF_USAGE
$PRODUCT_NAME $VERSION

Usage:
  $0 status
  $0 features
  $0 off [--keep feature[,feature...]] [--dry-run] [--yes]
  $0 revert [--yes]
  $0 selftest

The mutating commands target macOS $TARGET_MAJOR.x on Apple silicon.
EOF_USAGE
}

main() {
  local command="${1:-status}"
  shift || true
  case "$command" in
    status) require_platform; status_command "$@" ;;
    features) [[ "$#" -eq 0 ]] || fail 'features takes no options'; print_features ;;
    off) require_platform; off_command "$@" ;;
    revert) require_platform; parse_args "$@"; revert_command ;;
    selftest) [[ "$#" -eq 0 ]] || fail 'selftest takes no options'; selftest_command ;;
    --help|-h|help) usage ;;
    --version|-v|version) echo "$VERSION" ;;
    *) usage >&2; exit 1 ;;
  esac
}

main "$@"
