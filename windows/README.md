# stealthAI Windows

A native Win32 build of stealthAI with a small executable footprint and system WebView runtime usage.

## Why this stays lightweight

- Native Win32 C++ app (no Electron/Tauri runtime bundle)
- Uses installed Microsoft Edge WebView2 Runtime (not packaged in this repo)
- Release binary is optimized for size and dead-code elimination

## Features

- Always-on-top floating panel
- Hidden from taskbar/Alt-Tab (`WS_EX_TOOLWINDOW`)
- Global hotkeys
- Multi-tab web workspace (up to 10 tabs)
- Adjustable opacity
- Adjustable acrylic blur overlay strength
- Grayscale mode toggle
- Transparent page background toggle
- External popup/new-window links open in the native default browser

## Default Hotkeys

- Toggle panel: `Ctrl+Shift+Space`
- Switch tab: `Ctrl+Shift+Tab`
- Refresh current tab: `Ctrl+Shift+R`
- Decrease opacity: `Ctrl+Shift+[`
- Increase opacity: `Ctrl+Shift+]`
- Decrease blur: `Ctrl+Shift+;`
- Increase blur: `Ctrl+Shift+'`
- Toggle grayscale: `Ctrl+Shift+G`
- Toggle transparent background: `Ctrl+Shift+T`
- Reload settings from disk: `Ctrl+Shift+L`

## Settings

Settings file path:

`%APPDATA%\StealthAI\settings.ini`

Open it via the app's **Settings** button, edit tabs/visual values, then click **Reload** (or press `Ctrl+Shift+L`).

## Local Build (Windows)

PowerShell:

```powershell
./windows/scripts/build_release.ps1
```

Build output:

- `windows/dist/stealthAI-windows-x64.zip`

## Build Inputs

- Visual Studio 2022 Build Tools
- CMake 3.20+
- WebView2 SDK (downloaded by build script)
- WebView2 Runtime installed on target machine
