#!/bin/bash
# يبني Arab Writer.app من الحزمة ويجهز ملف zip و dmg للنشر.
# الاستعمال: scripts/build_app.sh [version]
set -euo pipefail

VERSION="${1:-1.0.0}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/dist"
APP="$OUT/Arab Writer.app"
RES="$ROOT/Sources/ArabWriter/Resources"

cd "$ROOT"
rm -rf "$OUT" && mkdir -p "$OUT"

echo "› البناء (Apple Silicon + Intel)"
swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/ArabWriter"

echo "› تجميع التطبيق"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ArabWriter"
cp -R "$RES/Skill" "$APP/Contents/Resources/Skill"
cp "$RES"/Amiri-*.ttf "$RES/OFL.txt" "$APP/Contents/Resources/"
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
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
else
  codesign --force --sign - "$APP"   # توقيع محلي (بدون حساب مطوّر)
fi
codesign --verify --verbose "$APP"

echo "› الحزم"
ditto -c -k --keepParent "$APP" "$OUT/Arab-Writer-$VERSION.zip"
STAGE="$OUT/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Arab Writer" -srcfolder "$STAGE" -ov -format UDZO "$OUT/Arab-Writer-$VERSION.dmg" >/dev/null
rm -rf "$STAGE"

echo "✓ جاهز: $OUT"
ls -la "$OUT"
