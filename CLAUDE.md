# macp — Mac App Control Protocol

CLI tool for operating and debugging macOS applications from the command line.
Used by Claude Code (via the `macp` skill) to verify Mac app behavior after building.

## Build

```bash
swift build
# binary: .build/debug/macp
```

## Required Permissions

System Settings > Privacy & Security:
1. **Accessibility** — UI inspection and interaction
2. **Screen Recording** — Screenshots

`macp check-access` to verify.

## Commands (20)

```
Diagnostics:    check-access
App lifecycle:  list-apps, launch-app, activate-app, quit-app
Windows:        window-list, focus-window (--index or --title)
UI inspection:  ui-tree (--compact), read-element, wait-for
UI interaction: action (press/set-value/set-focus/show-menu), menu
Low-level:      click, drag, scroll, move-mouse, type-text, key-press
                (all accept --pid for auto-activation)
Utilities:      clipboard, screenshot
```

## Architecture

- `Macp.swift` — CLI entry point (ArgumentParser)
- `Commands.swift` — 20 subcommand definitions
- `AccessibilityService.swift` — macOS AXUIElement API wrapper
- `ScreenCapture.swift` — Screenshot with auto-downscaling
