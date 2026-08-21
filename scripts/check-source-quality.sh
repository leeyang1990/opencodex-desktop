#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FORMATTER="$(xcrun --find swift-format)"

cd "$PROJECT_DIR"
"$FORMATTER" lint --strict --parallel --configuration .swift-format --recursive Sources Tests

CREDENTIAL_PATTERN='(sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----)'
CREDENTIAL_FOUND=false

if command -v rg >/dev/null; then
  if rg -n \
    --hidden \
    --glob '!.git/**' \
    --glob '!.build/**' \
    --glob '!dist/**' \
    --glob '!.tmp/**' \
    --glob '!Assets/*.png' \
    --glob '!Assets/screenshots/*.png' \
    "$CREDENTIAL_PATTERN" \
    .; then
    CREDENTIAL_FOUND=true
  fi
else
  while IFS= read -r -d '' file; do
    if grep -E -n -H -I "$CREDENTIAL_PATTERN" "$file"; then
      CREDENTIAL_FOUND=true
    fi
  done < <(
    find . -type f \
      ! -path './.git/*' \
      ! -path './.build/*' \
      ! -path './dist/*' \
      ! -path './.tmp/*' \
      ! -path './Assets/*.png' \
      ! -path './Assets/screenshots/*.png' \
      -print0
  )
fi

if [[ "$CREDENTIAL_FOUND" == true ]]; then
  echo "source quality: possible credential detected" >&2
  exit 1
fi

echo "source quality: passed"
