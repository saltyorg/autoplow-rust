#!/usr/bin/env bash
# Fails if public files contain environment-specific details: IP addresses,
# private hostnames/domains, personal paths, credential sources, or wording
# that refers to a specific development or production machine.
# Run locally before committing; CI runs it on every change.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

# Files to scan: everything tracked or untracked except build output and this script.
mapfile -t files < <(find . -type f \
  -not -path './.git/*' -not -path '*/target/*' -not -path '*/node_modules/*' \
  -not -path './.claude/*' -not -path './scripts/check-public-docs.sh' \
  \( -name '*.md' -o -name '*.rs' -o -name '*.toml' -o -name '*.yml' -o -name '*.yaml' \
     -o -name '*.json' -o -name '*.sh' -o -name '*.html' -o -name '*.mjs' -o -name '*.js' \))

patterns=(
  # IPv4 addresses, except loopback/unspecified and RFC 5737 documentation ranges.
  '\b(?!127\.0\.0\.1\b)(?!0\.0\.0\.0\b)(?!192\.0\.2\.)(?!198\.51\.100\.)(?!203\.0\.113\.)([0-9]{1,3}\.){3}[0-9]{1,3}\b'
  # Loopback ports of real services observed on a host.
  '127\.0\.0\.1:[0-9]{2,5}'
  # Private/dev domains and e-mail addresses.
  '\b[a-z0-9-]+\.dev\.saltbox\.dev\b'
  '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[a-z]{2,}'
  # Host-specific paths and credential sources.
  '/srv/git/'
  '/home/[a-z]'
  'motd\.yml'
  '/root/\.config/'
  'autoplow-test'
  # Wording that ties text to a particular machine.
  '\b(dev|development|production|prod) (box|host|server|machine)\b'
  # Token-looking strings.
  '\bgh[pousr]_[A-Za-z0-9]{20,}'
  '(X-Plex-Token|api_?key|apikey|token)=[A-Za-z0-9_-]{16,}'
)

status=0
for pat in "${patterns[@]}"; do
  if hits=$(grep -nIP -i -- "$pat" "${files[@]}" 2>/dev/null); then
    printf 'Forbidden pattern: %s\n%s\n\n' "$pat" "$hits"
    status=1
  fi
done

if [[ $status -eq 0 ]]; then
  echo "check-public-docs: OK (${#files[@]} files scanned)"
fi
exit $status
