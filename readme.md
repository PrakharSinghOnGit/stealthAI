# StealthAI

StealthAI is a lightweight macOS floating panel app for running multiple web-based AI chats (or any web tabs) in a stealth-style overlay.

It is designed for:
- Fast tab switching across multiple web tools
- Adjustable transparency and blur for shoulder-surfing protection
- Keyboard-first control with global hotkeys
- Background tab continuity (tabs keep running when not selected)

## Features

- Floating non-activating panel
- Multi-tab webview workspace (up to 10 tabs)
- Global hotkeys for panel visibility, tab switch, visual controls, and refresh
- Adjustable window opacity
- Adjustable blur overlay intensity
- Optional grayscale mode
- Optional transparent page background mode
- Settings UI for tab list and editable hotkeys
- Build + release automation for GitHub Releases

## Requirements

- macOS
- Xcode (with command line tools)

## Project Structure

- `stealthAI/AppDelegate.swift` - main app logic, hotkeys, settings, webview lifecycle
- `stealthAI/StealthPanel.swift` - custom panel and click-through blur effect view
- `scripts/build_release.sh` - local release build script (creates zip artifact)
- `.github/workflows/release.yml` - GitHub Action for tagged release builds

## Run Locally

Use Xcode:

1. Open `stealthAI.xcodeproj`
2. Select scheme `stealthAI`
3. Build and run

Or use terminal:

```bash
xcodebuild -project stealthAI.xcodeproj -scheme stealthAI -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

## Default Hotkeys

- Toggle panel: `cmd+shift+space`
- Switch tab: `cmd+shift+tab`
- Refresh current tab: `cmd+shift+r`
- Decrease opacity: `cmd+shift+[`
- Increase opacity: `cmd+shift+]`
- Decrease blur: `cmd+shift+;`
- Increase blur: `cmd+shift+'`
- Toggle grayscale: `cmd+shift+g`
- Toggle transparent background: `cmd+shift+t`

All of these are editable in Settings.

## Performance Notes

StealthAI is tuned to reduce unnecessary rendering work while keeping background tabs alive.

Implemented optimizations:
- Only the active tab webview is attached to the visible view hierarchy
- Background tabs remain loaded and can continue processing
- Shared web process pool across tabs

Things that still affect heat and battery:
- Heavy websites running scripts in background tabs
- Strong transparency + blur + grayscale together
- Video/animation-heavy pages

For best efficiency:
- Keep blur moderate
- Use grayscale when possible
- Disable transparent background when not needed

## Build Release Artifact

The script below builds a Release app and produces a zip file:

```bash
./scripts/build_release.sh
```

Output:

- `dist/stealthAI-macos.zip`

## GitHub Release Automation

The workflow at `.github/workflows/release.yml`:

- Triggers on pushed tags matching `v*` (for example `v1.0.0`)
- Builds on `macos-latest`
- Runs `./scripts/build_release.sh`
- Uploads `dist/stealthAI-macos.zip` to the GitHub Release page

### How to Publish a Release

```bash
git tag v1.0.0
git push origin v1.0.0
```

Once the workflow finishes, the zip artifact is attached to the release.

## Notes

- This project currently builds unsigned artifacts (`CODE_SIGNING_ALLOWED=NO`) for CI packaging.
- If you plan to distribute outside development/testing, add proper signing and notarization.

