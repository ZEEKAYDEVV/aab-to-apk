#!/usr/bin/env python3
"""
AAB -> APK  (one click, no keystore, no Java install needed when built)

How to use:
  * Open the app -> pick one or more .aab files -> APKs are made next to them.
  * Or drag .aab files onto the app icon (Windows .exe / macOS .app).

When built with build_mac.sh / build_windows.ps1 the app carries its own:
  - bundletool .jar
  - Java runtime   (folder "runtime")
  - debug.keystore (so every APK is signed and installs on any phone)
Running the plain .py instead? Then it falls back to Java on PATH and
bundletool*.jar next to the script.
"""
import glob
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import zipfile
import tkinter as tk
from tkinter import ttk, filedialog, messagebox

FROZEN = getattr(sys, "frozen", False)
APP_DIR = os.path.dirname(os.path.abspath(sys.executable if FROZEN else sys.argv[0]))
# PyInstaller puts bundled files in sys._MEIPASS; also look next to the app.
SEARCH_DIRS = list(dict.fromkeys([getattr(sys, "_MEIPASS", APP_DIR), APP_DIR]))
USER_KS = os.path.join(os.path.expanduser("~"), ".android", "debug.keystore")
PASS, ALIAS = "android", "androiddebugkey"
NO_WINDOW = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
EXE = ".exe" if os.name == "nt" else ""


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True, creationflags=NO_WINDOW)
    return r.returncode, (r.stdout + r.stderr).strip()


def bundled(*parts):
    for d in SEARCH_DIRS:
        p = os.path.join(d, *parts)
        if os.path.isfile(p):
            return p
    return None


def find_tool(name):
    """Bundled runtime first, then system PATH."""
    p = bundled("runtime", "bin", name + EXE)
    if p:
        if os.name != "nt" and not os.access(p, os.X_OK):
            try:
                os.chmod(p, 0o755)
            except OSError:
                pass
        return p
    return shutil.which(name)


def find_bundletool():
    jars = sorted(j for d in SEARCH_DIRS for j in glob.glob(os.path.join(d, "bundletool*.jar")))
    return jars[-1] if jars else None


def get_keystore():
    ks = bundled("debug.keystore")
    if ks:
        return ks
    if os.path.isfile(USER_KS):
        return USER_KS
    keytool = find_tool("keytool")
    if not keytool:
        raise RuntimeError("No signing key found and 'keytool' is missing. Install a JDK (11+).")
    os.makedirs(os.path.dirname(USER_KS), exist_ok=True)
    code, out = run([keytool, "-genkeypair", "-keystore", USER_KS, "-storepass", PASS,
                     "-alias", ALIAS, "-keypass", PASS, "-keyalg", "RSA",
                     "-keysize", "2048", "-validity", "10000",
                     "-dname", "CN=Android Debug,O=Android,C=US"])
    if code != 0:
        raise RuntimeError("Could not create signing key:\n" + out)
    return USER_KS


def convert(aab):
    """Convert one .aab to .apk next to it. Returns the apk path."""
    java = find_tool("java")
    if not java:
        raise RuntimeError("Java not found. Install a JDK (11+) from adoptium.net.")
    jar = find_bundletool()
    if not jar:
        raise RuntimeError("bundletool .jar not found. Put it in:\n" + APP_DIR)
    ks = get_keystore()

    apk = os.path.splitext(aab)[0] + ".apk"
    with tempfile.TemporaryDirectory() as tmp:
        apks = os.path.join(tmp, "out.apks")
        code, out = run([java, "-jar", jar, "build-apks",
                         f"--bundle={aab}", f"--output={apks}",
                         "--mode=universal", "--overwrite",
                         f"--ks={ks}", f"--ks-pass=pass:{PASS}",
                         f"--ks-key-alias={ALIAS}", f"--key-pass=pass:{PASS}"])
        if code != 0:
            raise RuntimeError(out[-1500:] or "bundletool failed.")
        with zipfile.ZipFile(apks) as z, z.open("universal.apk") as src, open(apk, "wb") as dst:
            shutil.copyfileobj(src, dst)
    return apk


def open_folder(folder):
    try:
        if os.name == "nt":
            os.startfile(folder)
        elif sys.platform == "darwin":
            subprocess.Popen(["open", folder])
        else:
            subprocess.Popen(["xdg-open", folder])
    except OSError:
        pass


class App(tk.Tk):
    def __init__(self, files):
        super().__init__()
        self.title("AAB → APK")
        self.geometry("540x320")
        self.resizable(False, False)
        f = ttk.Frame(self, padding=20)
        f.pack(fill="both", expand=True)
        ttk.Label(f, text="Convert Android App Bundles (.aab) to installable APKs",
                  font=("TkDefaultFont", 11, "bold")).pack(anchor="w", pady=(0, 10))
        self.btn = ttk.Button(f, text="Choose AAB file(s) → Get APK", command=self.pick)
        self.btn.pack(fill="x", ipady=14)
        self.bar = ttk.Progressbar(f, mode="determinate")
        self.bar.pack(fill="x", pady=12)
        self.status = tk.Text(f, height=8, wrap="word", state="disabled")
        self.status.pack(fill="both", expand=True)
        self.running = False
        if files:
            self.after(200, lambda: self.start(files))
        if sys.platform == "darwin":
            # macOS sends files dropped on the app icon as "open document" events
            self.createcommand("::tk::mac::OpenDocument", self._mac_open)

    def _mac_open(self, *paths):
        files = [p for p in paths if p.lower().endswith(".aab")]
        if files and not self.running:
            self.start(files)

    def say(self, text):
        def _do():
            self.status.configure(state="normal")
            self.status.insert("end", text + "\n")
            self.status.see("end")
            self.status.configure(state="disabled")
        self.after(0, _do)

    def pick(self):
        files = filedialog.askopenfilenames(filetypes=[("Android App Bundle", "*.aab")])
        if files:
            self.start(list(files))

    def start(self, files):
        self.running = True
        self.btn.configure(state="disabled")
        self.bar.configure(maximum=len(files), value=0)
        threading.Thread(target=self.work, args=(files,), daemon=True).start()

    def work(self, files):
        done, failed = [], []
        for i, aab in enumerate(files, 1):
            name = os.path.basename(aab)
            self.say(f"⏳ {name} …")
            try:
                apk = convert(aab)
                done.append(apk)
                self.say(f"✅ {os.path.basename(apk)}")
            except Exception as e:
                failed.append(name)
                self.say(f"❌ {name}: {e}")
            self.after(0, lambda v=i: self.bar.configure(value=v))

        def _end():
            self.running = False
            self.btn.configure(state="normal")
            msg = f"{len(done)} APK(s) created next to the AAB files."
            if failed:
                messagebox.showwarning("Finished", msg + f"\n{len(failed)} failed – see the list.")
            else:
                messagebox.showinfo("Done", msg)
            if done:
                open_folder(os.path.dirname(done[-1]))
        self.after(0, _end)


if __name__ == "__main__":
    dropped = [p for p in sys.argv[1:] if p.lower().endswith(".aab")]
    App(dropped).mainloop()
