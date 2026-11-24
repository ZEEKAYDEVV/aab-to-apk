# Builds "AAB to APK" for Windows with bundletool, a Java runtime and a
# debug signing key packed inside, so users need nothing else installed.
#
# Needs on the BUILD PC only: Python 3 (python.org, tick "Add to PATH")
# and a JDK 17+ (Temurin from adoptium.net).
# Run (in this folder):
#   powershell -ExecutionPolicy Bypass -File build_windows.ps1
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
$AppName = "AAB to APK"
function Say($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Die($m) { Write-Host "`nERROR: $m" -ForegroundColor Red; exit 1 }

# ---------- 1. Python ----------
Say "Checking Python"
$py = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $py) { $py = (Get-Command py -ErrorAction SilentlyContinue).Source }
if (-not $py) { Die "Python not found. Install it from https://www.python.org/downloads/ (tick 'Add to PATH')." }
& $py -c "import tkinter"
if ($LASTEXITCODE -ne 0) { Die "Your Python has no tkinter. Reinstall Python from python.org with 'tcl/tk' ticked." }

# ---------- 2. JDK ----------
Say "Looking for a JDK"
$jdk = $null
$candidates = @($env:JAVA_HOME)
$candidates += Get-ChildItem "C:\Program Files\Eclipse Adoptium", "C:\Program Files\Java", "C:\Program Files\Microsoft" -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }
$candidates += "C:\Program Files\Android\Android Studio\jbr"
$fallback = $null
foreach ($c in $candidates) {
  if (-not ($c -and (Test-Path "$c\bin\java.exe"))) { continue }
  if (Test-Path "$c\jmods") { $jdk = $c; break }   # full JDK: can make a small runtime
  if (-not $fallback) { $fallback = $c }
}
if (-not $jdk) { $jdk = $fallback }
if (-not $jdk) { Die "No Java found. Install Temurin 21 from https://adoptium.net" }
Write-Host "Using JDK: $jdk"

# ---------- 3. bundletool ----------
Say "Getting bundletool"
$jar = Get-ChildItem "bundletool-all-*.jar" -ErrorAction SilentlyContinue | Select-Object -Last 1
if (-not $jar) {
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  $rel = Invoke-RestMethod "https://api.github.com/repos/google/bundletool/releases/latest"
  $asset = $rel.assets | Where-Object { $_.name -like "bundletool-all-*.jar" } | Select-Object -First 1
  if (-not $asset) { Die "Could not find bundletool. Download bundletool-all-*.jar from github.com/google/bundletool/releases into this folder." }
  Invoke-WebRequest $asset.browser_download_url -OutFile $asset.name
  $jar = Get-Item $asset.name
}
Write-Host "Using $($jar.Name)"

# ---------- 4. Small Java runtime ----------
Say "Building a small Java runtime (jlink)"
$want = "java.base java.logging java.xml java.naming java.management java.sql java.desktop java.prefs java.scripting jdk.crypto.ec jdk.crypto.cryptoki jdk.crypto.mscapi jdk.zipfs jdk.unsupported jdk.charsets".Split(" ")
$have = & "$jdk\bin\java.exe" --list-modules | ForEach-Object { ($_ -split "@")[0] }
$mods = ($want | Where-Object { $have -contains $_ }) -join ","
if (Test-Path runtime) { Remove-Item runtime -Recurse -Force }
$ErrorActionPreference = "Continue"
& "$jdk\bin\jlink.exe" --add-modules $mods --strip-debug --no-header-files --no-man-pages --output runtime 2>$null
$ErrorActionPreference = "Stop"
if ($LASTEXITCODE -ne 0) {
  Write-Host "This Java can't make a small runtime - copying the whole Java instead (bigger app)."
  if (Test-Path runtime) { Remove-Item runtime -Recurse -Force }
  Copy-Item $jdk runtime -Recurse
  foreach ($x in "jmods","include","man","lib\src.zip","demo","sample") { if (Test-Path "runtime\$x") { Remove-Item "runtime\$x" -Recurse -Force } }
}
& .\runtime\bin\java.exe -version

# ---------- 5. Debug signing key ----------
Say "Creating debug signing key"
if (-not (Test-Path debug.keystore)) {
  & "$jdk\bin\keytool.exe" -genkeypair -keystore debug.keystore -storepass android `
    -alias androiddebugkey -keypass android -keyalg RSA -keysize 2048 `
    -validity 10000 -dname "CN=Android Debug,O=Android,C=US"
  if ($LASTEXITCODE -ne 0) { Die "keytool failed." }
}

# ---------- 6. Package the app ----------
Say "Installing PyInstaller"
& $py -m venv .venv
& .\.venv\Scripts\python.exe -m pip install --quiet --upgrade pip pyinstaller

Say "Building $AppName.exe"
if (Test-Path build) { Remove-Item build -Recurse -Force }
if (Test-Path dist)  { Remove-Item dist  -Recurse -Force }
& .\.venv\Scripts\pyinstaller.exe --noconfirm --windowed --name $AppName `
  --add-data "$($jar.Name);." `
  --add-data "debug.keystore;." `
  --add-data "runtime;runtime" `
  aab_to_apk.py
if ($LASTEXITCODE -ne 0) { Die "PyInstaller failed." }

Say "Zipping"
Compress-Archive -Path "dist\$AppName" -DestinationPath "dist\AAB-to-APK-Windows.zip" -Force

Say "Done!"
Write-Host "App: $PWD\dist\$AppName\$AppName.exe"
Write-Host "Zip: $PWD\dist\AAB-to-APK-Windows.zip   (share this one)"
if (-not $env:CI) { Invoke-Item dist }
