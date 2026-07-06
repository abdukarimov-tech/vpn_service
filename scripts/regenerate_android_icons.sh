#!/usr/bin/env bash
# Regenerate Android adaptive icons with full-bleed transparent foreground.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

python3 scripts/prepare_icon_foreground.py
(cd client && dart run flutter_launcher_icons)

# flutter_launcher_icons always adds 16% inset; we want full-bleed foreground.
cat > client/android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
  <background android:drawable="@color/ic_launcher_background"/>
  <foreground android:drawable="@drawable/ic_launcher_foreground"/>
</adaptive-icon>
XML

python3 scripts/generate_icon_preview.py
echo "Done. Previews: docs/icon-previews/all-devices-grid.png"
