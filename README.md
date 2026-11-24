# AAB to APK

One-click converter from Android App Bundles (`.aab`) to installable `.apk` files.
It needs no keystore and no Java install for the people who use it.

## Using the app
- Open **AAB to APK**, click **Choose AAB file(s) → Get APK**, and pick one or more `.aab` files.
- You can also drag `.aab` files onto the app icon.
- Each `.apk` is saved next to its `.aab`, and the folder opens when it's done.

The APK is signed with a built-in debug key, so it installs on any phone.
It can't install over a Play Store version of the same game, because the
signatures differ. Uninstall the Play version first.

## Building it

### macOS (on your Mac)
```bash
cd AAB-to-APK
bash build_mac.sh
```
You need Python 3 (from python.org) and a JDK 17 or newer (Temurin from
adoptium.net, or the JDK inside Android Studio).
Output: `dist/AAB to APK.app` and `dist/AAB-to-APK-macOS.zip`.

### Windows (on a Windows PC)
```powershell
cd AAB-to-APK
powershell -ExecutionPolicy Bypass -File build_windows.ps1
```
You need Python 3 (from python.org, with "Add to PATH" ticked) and a JDK 17 or newer (Temurin).
Output: `dist\AAB to APK\AAB to APK.exe` and `dist\AAB-to-APK-Windows.zip`.

### Both at once on GitHub (no Windows PC needed)
1. Push this folder to a GitHub repo, including `.github/workflows/build.yml`.
2. Go to **Actions → Build AAB to APK → Run workflow**.
3. Download both zips from the run's **Artifacts** section.

The macOS build on GitHub is for Apple Silicon Macs. For Intel Macs, build on an
Intel Mac with `build_mac.sh`.

## First launch warnings (the app is not code-signed)
- **macOS:** right-click the app → **Open** → **Open**. You only need to do this once.
- **Windows:** "Windows protected your PC" → **More info** → **Run anyway**.

## What's inside the built app
- `bundletool-all-*.jar`: Google's official AAB tool (downloaded automatically at build time)
- `runtime/`: a small Java runtime made with jlink, so users don't need Java
- `debug.keystore`: a debug signing key (password `android`, alias `androiddebugkey`)
