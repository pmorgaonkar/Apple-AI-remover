#!/bin/bash
set -euo pipefail

output="${1:-./uaf-reset}"
script_dir="$(cd "$(dirname "$0")" && pwd)"

command -v clang >/dev/null 2>&1 || { echo 'error: clang is required' >&2; exit 1; }
[[ -r "$script_dir/uaf-reset.m" ]] || { echo 'error: uaf-reset.m is missing' >&2; exit 1; }

clang -O2 -fobjc-arc -framework Foundation -framework CoreFoundation \
  -o "$output" "$script_dir/uaf-reset.m"
chmod 755 "$output"
printf 'built %s\n' "$output"
