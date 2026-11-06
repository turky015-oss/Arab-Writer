#!/bin/bash
# يبني Arab Writer.app (معالجات أبل) مع النموذج الداخلي، ويجهز zip و dmg.
# الاستعمال: scripts/build_app.sh [version]
# النموذج يُنزَّل مسبقاً إلى مجلد Model في جذر المشروع (scripts/fetch_model.sh).
set -euo pipefail

VERSION="${1:-1.0.0}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/dist"
APP="$OUT/Arab Writer.app"
RES="$ROOT/Sources/ArabWriter/Resources"
DD="$ROOT/.build/xcode"

cd "$ROOT"
rm -rf "$OUT" && mkdir -p "$OUT"

echo "› البناء (Xcode، حتى تُبنى شيفرات الرسوميات الخاصة بـ MLX)"
xcodebuild -scheme ArabWriter -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$DD" \
  -skipPackagePluginValidation -skipMacroValidation \
  ONLY_ACTIVE_ARCH=YES build > "$OUT/xcodebuild.log" 2>&1 || {
    grep -E "error:" "$OUT/xcodebuild.log" | sort -u | head -30 | while IFS= read -r l; do echo "::error::$l"; done
    tail -n 30 "$OUT/xcodebuild.log"; exit 1; }
  tail -n 5 "$OUT/xcodebuild.log"
PROD="$DD/Build/Products/Release"
test -f "$PROD/ArabWriter"

echo "› تجميع التطبيق"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$PROD/ArabWriter" "$APP/Contents/MacOS/ArabWriter"
for b in "$PROD"/*.bundle; do [ -e "$b" ] && cp -R "$b" "$APP/Contents/Resources/"; done
METAL=$(find "$PROD" "$DD" -name "*.metallib" -print -quit 2>/dev/null || true)
if [ -n "$METAL" ]; then
  cp "$METAL" "$APP/Contents/MacOS/mlx.metallib"
  cp "$METAL" "$APP/Contents/Resources/default.metallib"
  cp "$METAL" "$APP/Contents/Resources/mlx.metallib"
  echo "  metallib: $METAL"
else
  echo "::warning::ما لقيت metallib، النموذج الداخلي ممكن ما يشتغل"
fi
cp -R "$RES/Skill" "$APP/Contents/Resources/Skill"
cp "$RES"/Amiri-*.ttf "$RES/OFL.txt" "$APP/Contents/Resources/"
if [ -f "$ROOT/Model/config.json" ]; then
  cp -R "$ROOT/Model" "$APP/Contents/Resources/Model"
  echo "  النموذج: $(du -sh "$APP/Contents/Resources/Model" | cut -f1)"
fi
sed "s/__VERSION__/$VERSION/g" "$ROOT/scripts/Info.plist" > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "› الأيقونة"
ICON_SRC="$ROOT/Branding/AppIcon-1024.png"
SET="$OUT/AppIcon.iconset"
mkdir -p "$SET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$ICON_SRC" --out "$SET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$ICON_SRC" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$SET"

echo "› التوقيع"
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
else
  codesign --force --deep --sign - "$APP"
fi
codesign --verify --verbose "$APP"

echo "› الحزمة"
STAGE="$OUT/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Arab Writer" -srcfolder "$STAGE" -ov -format ULFO "$OUT/Arab-Writer-$VERSION.dmg" >/dev/null
rm -rf "$STAGE"

echo "✓ جاهز"
ls -la "$OUT"
