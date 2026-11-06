#!/bin/bash
# ينزّل النموذج الداخلي للماك إلى مجلد Model.
# Qwen2.5-3B-Instruct بدقة 4 بت (رخصة Qwen Research، يدعم العربية).
set -euo pipefail
REPO="${MODEL_REPO:-mlx-community/Qwen2.5-3B-Instruct-4bit}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Model"
mkdir -p "$DEST"
files=$(curl -fsSL "https://huggingface.co/api/models/$REPO/tree/main" | python3 -c "import sys,json;[print(f['path']) for f in json.load(sys.stdin) if f['type']=='file' and not f['path'].startswith('.') and f['path']!='README.md']")
for f in $files; do
  if [ ! -s "$DEST/$f" ]; then
    echo "  ↓ $f"
    curl -fsSL --retry 4 -o "$DEST/$f" "https://huggingface.co/$REPO/resolve/main/$f"
  fi
done
du -sh "$DEST"
