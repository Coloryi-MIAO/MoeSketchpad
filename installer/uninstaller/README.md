# MoeSketchpad Uninstaller

Standalone Windows uninstaller for MoeSketchpad.

The installer copies `moesketchpad_uninstaller.exe` into the installation
directory and registers it as the Add/Remove Programs entry:

```
"<install dir>\moesketchpad_uninstaller.exe" --install-dir="<install dir>"
```

It reverses everything the installer wrote:

1. the `.moesp` file association (`HKCU\Software\Classes\.moesp` and the
   `MoeSketchpad.Document` ProgID),
2. the desktop and Start menu shortcuts,
3. the installation directory entry in the user `PATH`,
4. the Add/Remove Programs registry key,
5. the installation directory itself (best-effort; the running uninstaller
   executable is skipped).

The manifest written at install time (`install_info.json`) records which of
those integration steps were actually performed, so the uninstaller only
touches what exists.

## Building

```sh
flutter pub get
flutter build windows --release
```

The executable lands in `build/windows/x64/runner/Release/`.
