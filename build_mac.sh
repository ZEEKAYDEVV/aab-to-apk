#!/bin/bash
# Builds "AAB to APK.app" for macOS with bundletool, a Java runtime and a
# debug signing key packed inside, so users need nothing else installed.
#
# Needs on the BUILD Mac only: Python 3 (python.org installer recommended)
# and a JDK 17+ (Temurin from adoptium.net, or the one inside Android Studio).
# Run:  cd AAB-to-APK && bash build_mac.sh
set -euo pipefail
cd "$(dirname "$0")"
APP_NAME="AAB to APK"

say() { printf "\n\033[1;34m==> %s\033[0m\n" "$1"; }
die() { printf "\n\033[1;31mERROR: %s\033[0m\n" "$1"; exit 1; }

# ---------- 1. Python ----------
say "Checking Python"
PY=$(command -v python3 || true)
[ -n "$PY" ] || die "python3 not found. Install it from https://www.python.org/downloads/"
"$PY" -c "import tkinter" 2>/dev/null || die "Your Python has no tkinter. Install Python from python.org (or: brew install python-tk)."

# ---------- 2. JDK (needs jlink) ----------
say "Looking for a JDK"
JDK=""; FALLBACK=""
CANDS=("${JAVA_HOME:-}" "$(/usr/libexec/java_home 2>/dev/null || true)")
for d in /Library/Java/JavaVirtualMachines/*/Contents/Home "$HOME"/Library/Java/JavaVirtualMachines/*/Contents/Home; do CANDS+=("$d"); done
CANDS+=("/Applications/Android Studio.app/Contents/jbr/Contents/Home" "/Applications/Android Studio.app/Contents/jbr")
for c in "${CANDS[@]}"; do
  { [ -n "$c" ] && [ -x "$c/bin/java" ]; } || continue
  if [ -d "$c/jmods" ]; then JDK="$c"; break; fi   # full JDK: can make a small runtime
  [ -n "$FALLBACK" ] || FALLBACK="$c"
done
[ -n "$JDK" ] || JDK="$FALLBACK"
[ -n "$JDK" ] || die "No Java found. Install Temurin 21 from https://adoptium.net"
echo "Using JDK: $JDK"

# ---------- 3. bundletool ----------
say "Getting bundletool"
JAR=$(ls bundletool-all-*.jar 2>/dev/null | tail -n1 || true)
if [ -z "$JAR" ]; then
  URL=$(curl -fsSL https://api.github.com/repos/google/bundletool/releases/latest \
        | grep -o '"browser_download_url": *"[^"]*bundletool-all-[^"]*\.jar"' \
        | head -n1 | sed 's/.*"\(https[^"]*\)"/\1/')
  [ -n "$URL" ] || die "Could not find bundletool download. Download bundletool-all-*.jar from github.com/google/bundletool/releases into this folder."
  curl -fL -o "$(basename "$URL")" "$URL"
  JAR=$(basename "$URL")
fi
echo "Using $JAR"

# ---------- 4. Small Java runtime ----------
say "Building a small Java runtime (jlink)"
WANT="java.base java.logging java.xml java.naming java.management java.sql java.desktop java.prefs java.scripting jdk.crypto.ec jdk.crypto.cryptoki jdk.zipfs jdk.unsupported jdk.charsets"
HAVE=$("$JDK/bin/java" --list-modules | sed 's/@.*//')
MODS=$(for m in $WANT; do echo "$HAVE" | grep -qx "$m" && echo "$m"; done | paste -sd, -)
rm -rf runtime
if ! "$JDK/bin/jlink" --add-modules "$MODS" --strip-debug --no-header-files --no-man-pages \
     --output runtime 2>/dev/null; then
  echo "This Java can't make a small runtime - copying the whole Java instead (bigger app)."
  rm -rf runtime
  cp -R "$JDK" runtime
  rm -rf runtime/jmods runtime/include runtime/man runtime/lib/src.zip runtime/demo runtime/sample
fi
runtime/bin/java -version

# ---------- 5. Debug signing key ----------
say "Creating debug signing key"
if [ ! -f debug.keystore ]; then
  "$JDK/bin/keytool" -genkeypair -keystore debug.keystore -storepass android \
    -alias androiddebugkey -keypass android -keyalg RSA -keysize 2048 \
    -validity 10000 -dname "CN=Android Debug,O=Android,C=US"
fi

# ---------- 6. Package the app ----------
say "Installing PyInstaller"
"$PY" -m venv .venv
.venv/bin/pip install --quiet --upgrade pip pyinstaller

say "Building $APP_NAME.app"
rm -rf build dist
.venv/bin/pyinstaller --noconfirm --windowed --name "$APP_NAME" \
  --osx-bundle-identifier com.tools.aabtoapk \
  --add-data "$JAR:." \
  --add-data "debug.keystore:." \
  --add-data "runtime:runtime" \
  aab_to_apk.py

# Let the app open .aab files (drag onto icon / "Open With")
PLIST="dist/$APP_NAME.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes array" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0 dict" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0:CFBundleTypeName string 'Android App Bundle'" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0:CFBundleTypeRole string Viewer" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0:CFBundleTypeExtensions array" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0:CFBundleTypeExtensions:0 string aab" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0:LSItemContentTypes array" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0:LSItemContentTypes:0 string public.data" "$PLIST"

# Make sure the bundled java is executable, then ad-hoc sign everything
find "dist/$APP_NAME.app" -path "*runtime/bin/*" -type f -exec chmod +x {} \;
find "dist/$APP_NAME.app" -path "*runtime/lib/jspawnhelper" -exec chmod +x {} \; 2>/dev/null || true
codesign --force --deep --sign - "dist/$APP_NAME.app"

say "Zipping"
(cd dist && ditto -c -k --keepParent "$APP_NAME.app" "AAB-to-APK-macOS.zip")

say "Done!"
echo "App:  $(pwd)/dist/$APP_NAME.app"
echo "Zip:  $(pwd)/dist/AAB-to-APK-macOS.zip   (share this one)"
open dist
