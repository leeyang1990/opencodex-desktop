#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FORMATTER="$(xcrun --find swift-format)"

cd "$PROJECT_DIR"
"$FORMATTER" lint --strict --parallel --configuration .swift-format --recursive Sources Tests

if rg -n \
  --hidden \
  --glob '!.git/**' \
  --glob '!.build/**' \
  --glob '!dist/**' \
  --glob '!.tmp/**' \
  --glob '!Assets/*.png' \
  --glob '!Assets/screenshots/*.png' \
  '(sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----)' \
  .; then
    echo "source quality: possible credential detected" >&2
    exit 1
fi

echo "source quality: passed"
