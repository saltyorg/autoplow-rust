#!/usr/bin/env bash
# Fails if any relative link in a markdown file points to a missing path.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
python3 - <<'PY'
import glob, os, re, sys
bad = []
for f in glob.glob("**/*.md", recursive=True):
    if "/target/" in f or "node_modules" in f:
        continue
    for m in re.finditer(r"\]\(([^)#\s]+)(#[^)]*)?\)", open(f, encoding="utf-8").read()):
        t = m.group(1)
        if t.startswith(("http://", "https://", "mailto:")):
            continue
        if not os.path.exists(os.path.normpath(os.path.join(os.path.dirname(f), t))):
            bad.append(f"{f}: {t}")
print("\n".join(bad) if bad else "check-links: OK")
sys.exit(1 if bad else 0)
PY
