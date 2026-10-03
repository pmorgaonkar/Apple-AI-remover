#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

clang -O2 -fobjc-arc -framework Foundation -o uaf-reset uaf-reset.m

echo "Built ./uaf-reset"
