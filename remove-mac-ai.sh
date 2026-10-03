#!/bin/bash
set -euo pipefail

VERSION=0.3.2
NAME='Apple AI remover'
PROFILE_ID='io.github.pmorgaonkar.apple-ai-remover'
LEGACY_PROFILE_ID='io.github.omlahore.removemacai.bash'
UPSTREAM_PROFILE_ID='io.github.omlahore.removemacai'
PROFILE_NAME='Apple AI remover'
PROFILE_FILE="$HOME/Downloads/Apple-AI-remover.mobileconfig"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_SCRIPT="$SCRIPT_DIR/build-helper.sh"
HELPER_SOURCE="$SCRIPT_DIR/uaf-reset.m"
BLOCKED_URL='https://127.0.0.1:9/apple-ai-remover-blocked/'
TARGET_MAJOR=27

FEATURES=(siri chatgpt writing-tools genmoji image-playground mail notification-summaries messages-summaries safari-summaries notes-summaries inline-predictions spatial-photos photos-clean-up xcode-completion)
MODEL_SETS=(com.apple.modelcatalog com.apple.MobileAsset.UAF.FM.Visual com.apple.MobileAsset.UAF.Photos.SpatialPhotosRelive com.apple.MobileAsset.UAF.Photos.MagicCleanup com.apple.MobileAsset.UAF.FM.CodeLM)
KEEP=()
DRY_RUN=0
YES=0
HELPER_DIR=''
HELPER=''

fail() { printf 'error: %s\n' "$*" >&2; exit 1; }
warn() { printf 'warning: %s\n' "$*" >&2; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"; }

require_platform() {
  [[ "$(uname -s)" == Darwin ]] || fail 'this utility runs on macOS'
  [[ "$(uname -m)" == arm64 ]] || fail 'this release targets Apple silicon (arm64)'
  local v="$(sw_vers -productVersion)"
  [[ "${v%%.*}" == "$TARGET_MAJOR" ]] || fail "unsupported macOS $v; this release targets macOS $TARGET_MAJOR.x"
}

cleanup() { [[ -z "$HELPER_DIR" ]] || rm -rf "$HELPER_DIR"; }

build_helper() {
  need_cmd clang
  need_cmd mktemp
  [[ -r "$HELPER_SOURCE" && -x "$BUILD_SCRIPT" ]] || fail 'native helper source/build script missing or not executable'
  if [[ -x "$HELPER" ]]; then return 0; fi
  HELPER_DIR="$(mktemp -d "${TMPDIR:-/tmp}/apple-ai-remover.XXXXXX")"
  HELPER="$HELPER_DIR/uaf-reset"
  trap cleanup EXIT HUP INT TERM
  "$BUILD_SCRIPT" "$HELPER" >/dev/null || fail 'native helper build failed'
}

title() {
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

restriction_keys() {
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

preference_rows() {
  case "$1" in
    siri)
      printf '%s\t%s\tfalse\n' com.apple.assistant.support 'Assistant Enabled'
      printf '%s\t%s\tfalse\n' com.apple.Siri StatusMenuVisible
      printf '%s\t%s\tfalse\n' com.apple.Siri VoiceTriggerUserEnabled ;;
    mail)
      printf '%s\t%s\ttrue\n' group.com.apple.mail DisableAutomaticMessageSummarization
      printf '%s\t%s\tfalse\n' group.com.apple.mail PersonalizedSmartReplies ;;
    notification-summaries) printf '%s\t%s\tfalse\n' group.com.apple.usernoted summarize_previews ;;
    messages-summaries) printf '%s\t%s\tfalse\n' com.apple.MobileSMS messageSummarizationEnabled ;;
    inline-predictions) printf '%s\t%s\tfalse\n' .GlobalPreferences NSAutomaticInlinePredictionEnabled ;;
    spatial-photos) printf '%s\t%s\ttrue\n' com.apple.spatialphotosrelive LocallyDisabled ;;
  esac
}

feature_sets() {
  case "$1" in
    siri|writing-tools|mail|notification-summaries|messages-summaries|safari-summaries|notes-summaries) echo com.apple.modelcatalog ;;
    genmoji|image-playground) printf '%s\n' com.apple.modelcatalog com.apple.MobileAsset.UAF.FM.Visual ;;
    spatial-photos) echo com.apple.MobileAsset.UAF.Photos.SpatialPhotosRelive ;;
    photos-clean-up) echo com.apple.MobileAsset.UAF.Photos.MagicCleanup ;;
    xcode-completion) echo com.apple.MobileAsset.UAF.FM.CodeLM ;;
  esac
}

asset_type() {
  case "$1" in
    com.apple.modelcatalog) echo com.apple.MobileAsset.UAF.FM.GenerativeModels ;;
    com.apple.MobileAsset.UAF.FM.Visual) echo com.apple.MobileAsset.UAF.FM.Visual ;;
    com.apple.MobileAsset.UAF.Photos.SpatialPhotosRelive) echo com.apple.MobileAsset.UAF.Photos.SpatialPhotosRelive ;;
    com.apple.MobileAsset.UAF.Photos.MagicCleanup) echo com.apple.MobileAsset.UAF.Photos.MagicCleanup ;;
    com.apple.MobileAsset.UAF.FM.CodeLM) echo com.apple.MobileAsset.UAF.FM.CodeLM ;;
    *) return 1 ;;
  esac
}

model_title() {
  case "$1" in
    com.apple.modelcatalog) echo 'Apple Intelligence foundation models' ;;
    com.apple.MobileAsset.UAF.FM.Visual) echo 'Image and Genmoji models' ;;
    com.apple.MobileAsset.UAF.Photos.SpatialPhotosRelive) echo 'Spatial Photos models' ;;
    com.apple.MobileAsset.UAF.Photos.MagicCleanup) echo 'Photos Clean Up models' ;;
    com.apple.MobileAsset.UAF.FM.CodeLM) echo 'Xcode code completion models' ;;
    *) return 1 ;;
  esac
}

kept() { local x; for x in "${KEEP[@]:-}"; do [[ -n "$x" && "$x" == "$1" ]] && return 0; done; return 1; }

parse_keep() {
  local raw="$1" old_ifs="$IFS" x
  local -a values
  IFS=','; read -r -a values <<< "$raw"; IFS="$old_ifs"
  for x in "${values[@]}"; do
    x="$(printf '%s' "$x" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -z "$x" ]] && continue
    title "$x" >/dev/null || fail "unknown feature '$x'"
    kept "$x" || KEEP+=("$x")
  done
}

parse_off_args() {
  KEEP=(); DRY_RUN=0; YES=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --keep) [[ $# -ge 2 ]] || fail '--keep requires a value'; parse_keep "$2"; shift 2 ;;
      --dry-run) DRY_RUN=1; shift ;;
      --yes|-y) YES=1; shift ;;
      *) fail "unknown option '$1'" ;;
    esac
  done
}

parse_yes_args() {
  YES=0
  while [[ $# -gt 0 ]]; do
    case "$1" in --yes|-y) YES=1; shift ;; *) fail "unknown option '$1'" ;; esac
  done
}

sets_to_remove() {
  local target feature set remove
  for target in "${MODEL_SETS[@]}"; do
    remove=1
    for feature in "${FEATURES[@]}"; do
      while IFS= read -r set; do
        [[ "$set" == "$target" ]] || continue
        kept "$feature" && remove=0
      done < <(feature_sets "$feature")
    done
    (( remove == 1 )) && printf '%s\n' "$target"
  done
}

xml_escape() {
  local s="$1"
  s="${s//&/&amp;}"; s="${s//</&lt;}"; s="${s//>/&gt;}"; s="${s//\"/&quot;}"; s="${s//\'/&apos;}"
  printf '%s' "$s"
}

stable_uuid() {
  local name="$1" h variant
  h="$(printf '%s' "$name" | shasum -a 1 | awk '{print $1}')"
  variant=$((16#${h:16:2} & 63 | 128))
  printf '%s-%s-%s-%s-%s\n' "${h:0:8}" "${h:8:4}" "5${h:13:3}" "$(printf '%02x' "$variant")${h:18:2}" "${h:20:12}"
}

payload_header() {
  local type="$1" suffix="$2" display="$3" id="$PROFILE_ID.$suffix"
  printf '%s\n' '<dict>'
  printf '<key>PayloadType</key><string>%s</string>\n' "$(xml_escape "$type")"
  printf '%s\n' '<key>PayloadVersion</key><integer>1</integer>'
  printf '<key>PayloadIdentifier</key><string>%s</string>\n' "$(xml_escape "$id")"
  printf '<key>PayloadUUID</key><string>%s</string>\n' "$(stable_uuid "$id")"
  printf '<key>PayloadDisplayName</key><string>%s</string>\n' "$(xml_escape "$display")"
}

emit_pref_payload() {
  local domain="$1" suffix="$2" display="$3" rows="$4" key value
  [[ -n "$rows" ]] || return 0
  payload_header com.apple.ManagedClient.preferences "preferences.$suffix" "$display"
  printf '%s\n' '      <key>PayloadContent</key><dict>'
  printf '        <key>%s</key>\n' "$(xml_escape "$domain")"
  printf '%s\n' '        <dict><key>Forced</key><array><dict><key>mcx_preference_settings</key><dict>'
  while IFS=$'\t' read -r key value; do
    [[ -n "$key" ]] || continue
    case "$value" in
      true|false) printf '                <key>%s</key><%s/>\n' "$(xml_escape "$key")" "$value" ;;
      *) printf '                <key>%s</key><string>%s</string>\n' "$(xml_escape "$key")" "$(xml_escape "$value")" ;;
    esac
  done <<< "$rows"
  printf '%s\n' '              </dict></dict></array></dict></dict></dict>'
}

domain_rows() {
  local domain="$1" feature pd key value rows=''
  for feature in "${FEATURES[@]}"; do
    kept "$feature" && continue
    while IFS=$'\t' read -r pd key value; do
      [[ "$pd" == "$domain" ]] || continue
      rows="${rows}${key}"$'\t'"${value}"$'\n'
    done < <(preference_rows "$feature")
  done
  printf '%s' "$rows"
}

restriction_rows() {
  local feature key rows=''
  for feature in "${FEATURES[@]}"; do
    kept "$feature" && continue
    while IFS= read -r key; do [[ -n "$key" ]] && rows="${rows}${key}"$'\n'; done < <(restriction_keys "$feature")
  done
  printf '%s' "$rows"
}

download_rows() {
  local sets="$1" set key rows=''
  while IFS= read -r set; do
    [[ -n "$set" ]] || continue
    key="DownloadServerBaseURLOverride-$(asset_type "$set")"
    rows="${rows}${key}"$'\t'"${BLOCKED_URL}"$'\n'
  done <<< "$sets"
  printf '%s' "$rows"
}

keep_csv() { printf '%s' "${KEEP[*]:-}" | tr ' ' ','; }

build_profile() {
  local output="$1" sets="$2" tmp="$output.tmp.$$" domain rows restrictions assets
  restrictions="$(restriction_rows)"
  assets="$(download_rows "$sets")"
  mkdir -p "$(dirname "$output")"
  {
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
    printf '%s\n' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    printf '%s\n' '<plist version="1.0"><dict>'
    printf '%s\n' '<key>PayloadType</key><string>Configuration</string><key>PayloadVersion</key><integer>1</integer>'
    printf '<key>PayloadIdentifier</key><string>%s</string>\n' "$PROFILE_ID"
    printf '<key>PayloadUUID</key><string>%s</string>\n' "$(stable_uuid "$PROFILE_ID")"
    printf '<key>PayloadDisplayName</key><string>%s</string>\n' "$(xml_escape "$PROFILE_NAME")"
    printf '%s\n' '<key>PayloadDescription</key><string>Disables Apple Intelligence features and blocks selected model downloads. Remove this profile to undo.</string>'
    printf '%s\n' '<key>PayloadOrganization</key><string>Apple AI remover</string>'
    printf '%s\n' '<key>PayloadScope</key><string>System</string>'
    printf '%s\n' '<key>PayloadRemovalDisallowed</key><false/><key>PayloadContent</key><array>'
    if [[ -n "$restrictions" ]]; then
      payload_header com.apple.applicationaccess restrictions 'Apple Intelligence restrictions'
      printf '%s\n' '      <key>PayloadContent</key><dict>'
      while IFS= read -r key; do [[ -n "$key" ]] && printf '        <key>%s</key><false/>\n' "$(xml_escape "$key")"; done <<< "$restrictions"
      printf '%s\n' '      </dict></dict>'
    fi
    for domain in com.apple.assistant.support com.apple.Siri group.com.apple.mail group.com.apple.usernoted com.apple.MobileSMS .GlobalPreferences com.apple.spatialphotosrelive; do
      rows="$(domain_rows "$domain")"
      emit_pref_payload "$domain" "$domain" "Forced settings: $domain" "$rows"
    done
    emit_pref_payload com.apple.MobileAsset MobileAsset 'MobileAsset download overrides' "$assets"
    rows="installed"$'\t'true$'\n'"kept"$'\t'"$(keep_csv)"$'\n'
    emit_pref_payload "$PROFILE_ID" marker 'Apple AI remover state' "$rows"
    printf '%s\n' '</array></dict></plist>'
  } > "$tmp"
  /usr/bin/plutil -lint "$tmp" >/dev/null 2>&1 || { rm -f "$tmp"; fail 'generated profile failed plist validation'; }
  mv "$tmp" "$output"
}

helper_pref() { "$HELPER" pref "$1" "$2"; }
profile_installed() { local o; o="$(helper_pref "$PROFILE_ID" installed 2>/dev/null)" || return 1; [[ "$o" == *$'forced=1\tvalue=true'* ]]; }
legacy_profile_installed() { local o; o="$(helper_pref "$LEGACY_PROFILE_ID" installed 2>/dev/null)" || return 1; [[ "$o" == *$'forced=1\tvalue=true'* ]]; }
upstream_profile_installed() { local o; o="$(helper_pref "$UPSTREAM_PROFILE_ID" installed 2>/dev/null)" || return 1; [[ "$o" == *$'forced=1\tvalue=true'* ]]; }
profile_kept_csv() { local o; o="$(helper_pref "$PROFILE_ID" kept 2>/dev/null)" || return 1; printf '%s' "${o#*value=}"; }

validate_catalog() {
  local set expected actual
  for set in "${MODEL_SETS[@]}"; do
    expected="$(asset_type "$set")"
    actual="$($HELPER asset-type "$set")" || fail "UAF lookup failed for $set"
    [[ "$actual" == "$expected" ]] || fail "UAF mapping mismatch for $set: expected $expected, got $actual"
  done
}

model_bytes() { local out; out="$($HELPER bytes "$1" 2>/dev/null)" || return 1; [[ "$out" =~ ^[0-9]+$ ]] || return 1; printf '%s' "$out"; }
format_bytes() { local b="$1"; if (( b >= 1000000000 )); then awk -v n="$b" 'BEGIN { printf "%.1f GB", n/1e9 }'; elif (( b > 0 )); then awk -v n="$b" 'BEGIN { printf "%.0f MB", n/1e6 }'; else echo '0 MB'; fi; }

feature_state() {
  local feature="$1" domain key want out
  local pref_has=0 pref_forced=1 pref_off=1 restriction_has=0 restriction_forced=1
  while IFS=$'\t' read -r domain key want; do
    [[ -n "$domain" ]] || continue; pref_has=1
    out="$(helper_pref "$domain" "$key" 2>/dev/null)" || { echo unknown; return; }
    [[ "$out" == "forced=1"$'\t'"value=$want" ]] || pref_forced=0
    [[ "$out" == *$'\t'"value=$want" ]] || pref_off=0
  done < <(preference_rows "$feature")
  while IFS= read -r key; do
    [[ -n "$key" ]] || continue; restriction_has=1
    out="$(helper_pref com.apple.applicationaccess "$key" 2>/dev/null)" || { echo unknown; return; }
    [[ "$out" == *$'forced=1\tvalue=false'* ]] || restriction_forced=0
  done < <(restriction_keys "$feature")
  if (( pref_has || restriction_has )); then
    if (( (pref_has == 0 || pref_forced) && (restriction_has == 0 || restriction_forced) )); then echo locked; return; fi
    if (( pref_has && pref_off )); then echo off; else echo on; fi
    return
  fi
  if profile_installed && ! kept "$feature"; then echo locked; return; fi
  local set total=0 known=1 n
  while IFS= read -r set; do
    [[ -n "$set" ]] || continue
    if ! n="$(model_bytes "$set")"; then known=0; break; fi
    total=$((total+n))
  done < <(feature_sets "$feature")
  if (( known == 0 )); then echo unknown; elif (( total > 0 )); then echo on; else echo off; fi
}

status_command() {
  build_helper
  printf '%s %s · macOS %s\n\n' "$NAME" "$VERSION" "$(sw_vers -productVersion)"
  local feature set state bytes total=0
  for feature in "${FEATURES[@]}"; do state="$(feature_state "$feature")"; printf '%-42s %s\n' "$(title "$feature")" "$state"; done
  printf '\nModels on disk\n'
  for set in "${MODEL_SETS[@]}"; do if bytes="$(model_bytes "$set")"; then total=$((total+bytes)); printf '  %-42s %s\n' "$(model_title "$set")" "$(format_bytes "$bytes")"; else printf '  %-42s unknown\n' "$(model_title "$set")"; fi; done
  printf '  %-42s %s\n' Total "$(format_bytes "$total")"
  profile_installed && echo 'Profile: installed' || echo 'Profile: not-installed'
}

print_features() { local f; for f in "${FEATURES[@]}"; do printf '%-28s %s\n' "$f" "$(title "$f")"; done; }
open_profile_settings() { open 'x-apple.systempreferences:com.apple.Profiles-Settings.extension' 2>/dev/null || open 'x-apple.systempreferences:com.apple.preferences.configurationprofiles' 2>/dev/null || true; }
wait_for_profile() { local expected="$1" seconds=0; while (( seconds < 600 )); do if profile_installed && [[ "$(profile_kept_csv || true)" == "$expected" ]]; then return 0; fi; sleep 2; seconds=$((seconds+2)); done; return 1; }

confirm() { (( YES == 1 )) && return 0; [[ -t 0 ]] || fail 'run in a terminal or pass --yes'; printf 'Turn off Apple Intelligence and reset selected models? [y/N] '; read -r answer; [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]; }

off_command() {
  parse_off_args "$@"
  build_helper
  if legacy_profile_installed || upstream_profile_installed; then fail 'another RemoveMacAI profile is installed; remove it before using this implementation'; fi
  validate_catalog
  local sets="$(sets_to_remove)" feature expected
  printf 'Features to disable:\n'; for feature in "${FEATURES[@]}"; do kept "$feature" || printf '  - %s\n' "$(title "$feature")"; done
  printf 'Model sets to reset:\n'; if [[ -n "$sets" ]]; then printf '%s\n' "$sets" | sed 's/^/  - /'; else printf '  - none\n'; fi
  if (( DRY_RUN )); then local dry="${TMPDIR:-/tmp}/Apple-AI-remover.$$.mobileconfig"; build_profile "$dry" "$sets"; printf 'DRY RUN: no system changes made.\nGenerated profile: %s\n' "$dry"; return 0; fi
  confirm || { printf 'Nothing changed.\n'; return 0; }
  expected="$(keep_csv)"
  build_profile "$PROFILE_FILE" "$sets"
  open "$PROFILE_FILE" 2>/dev/null || true
  open_profile_settings
  printf 'Approve "%s" in System Settings.\n' "$PROFILE_NAME"
  wait_for_profile "$expected" || fail 'profile installation was not observed; no model reset was attempted'
  if [[ -n "$sets" ]]; then
    reset_models_failed=0
    while IFS= read -r feature; do [[ -n "$feature" ]] || continue; if "$HELPER" reset "$feature"; then printf 'reset: %s\n' "$feature"; else warn "asset reset failed: $feature"; reset_models_failed=1; fi; done <<< "$sets"
    (( reset_models_failed == 0 )) || fail 'one or more model resets failed; run status to inspect remaining state'
  fi
  printf 'Done. Run: ./remove-mac-ai.sh status\n'
}

revert_command() {
  parse_yes_args "$@"
  build_helper
  local current=0 legacy=0
  profile_installed && current=1; legacy_profile_installed && legacy=1
  (( current || legacy )) || { printf 'No Apple AI remover profile is installed.\n'; return 0; }
  if (( YES == 0 )); then [[ -t 0 ]] || fail 'run in a terminal or pass --yes'; printf 'Remove Apple AI remover profile(s)? [y/N] '; read -r answer; [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]] || { printf 'Nothing changed.\n'; return 0; }; fi
  (( current )) && sudo /usr/bin/profiles remove -identifier "$PROFILE_ID"
  (( legacy )) && sudo /usr/bin/profiles remove -identifier "$LEGACY_PROFILE_ID"
  printf 'Profile removal requested.\n'
}

selftest_command() {
  need_cmd shasum; need_cmd plutil
  [[ "${#FEATURES[@]}" -eq 14 ]] || fail 'unexpected feature count'
  [[ "${#MODEL_SETS[@]}" -eq 5 ]] || fail 'unexpected model-set count'
  local feature set all a b tmp
  for feature in "${FEATURES[@]}"; do title "$feature" >/dev/null || fail "missing feature title: $feature"; done
  for set in "${MODEL_SETS[@]}"; do asset_type "$set" >/dev/null || fail "missing model-set mapping: $set"; done
  KEEP=(); all="$(sets_to_remove)"; [[ "$(printf '%s\n' "$all" | sort)" == "$(printf '%s\n' "${MODEL_SETS[@]}" | sort)" ]] || fail 'dependency closure failed for empty keep set'
  KEEP=(writing-tools); all="$(sets_to_remove)"; ! grep -qx com.apple.modelcatalog <<< "$all" || fail 'writing-tools must keep foundation models'; grep -qx com.apple.MobileAsset.UAF.FM.Visual <<< "$all" || fail 'writing-tools must not keep visual models'
  KEEP=(); a="$(stable_uuid "$PROFILE_ID")"; b="$(stable_uuid "$PROFILE_ID")"; [[ "$a" == "$b" ]] || fail 'UUID generation is not stable'
  tmp="${TMPDIR:-/tmp}/apple-ai-remover-selftest.$$.mobileconfig"; build_profile "$tmp" "$(sets_to_remove)"; /usr/bin/plutil -lint "$tmp" >/dev/null 2>&1 || fail 'generated profile is invalid'; grep -q 'DownloadServerBaseURLOverride-com.apple.MobileAsset.UAF.FM.GenerativeModels' "$tmp" || fail 'foundation download override missing'; rm -f "$tmp"
  printf 'selftest: PASS (%s features, %s model sets)\n' "${#FEATURES[@]}" "${#MODEL_SETS[@]}"
}

usage() {
  cat <<EOF
$NAME $VERSION

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
    status) [[ $# -eq 0 ]] || fail 'status takes no options'; require_platform; status_command ;;
    features) [[ $# -eq 0 ]] || fail 'features takes no options'; print_features ;;
    off) require_platform; off_command "$@" ;;
    revert) require_platform; revert_command "$@" ;;
    selftest) [[ $# -eq 0 ]] || fail 'selftest takes no options'; selftest_command ;;
    --help|-h|help) usage ;;
    --version|-v|version) echo "$VERSION" ;;
    *) usage >&2; exit 1 ;;
  esac
}

main "$@"
