# macp — Mac App Control Protocol

Give [Claude Code](https://claude.ai/claude-code) the ability to see, interact with, and verify running macOS applications.

## The Problem

Claude Code can write code and ensure it compiles — but it can't verify the running app actually works. It can't see what's on screen, click a button, or check if a label shows the right text. You're stuck being the eyes and hands.

## The Solution

`macp` is a CLI tool that bridges this gap through the macOS Accessibility API. Once installed, Claude Code can:

- **Inspect** UI element trees to understand app structure
- **Interact** with buttons, menus, text fields — by role, title, or coordinates
- **Verify** state by reading element attributes or taking screenshots
- **Wait** for UI changes after actions

## Install

Requires **macOS 13+** and **Xcode 15+** (for Swift 5.9).

### Homebrew (recommended)

```bash
brew tap xiao99xiao/tap
brew install macp
```

### From source

```bash
git clone https://github.com/xiao99xiao/macp.git
cd macp
sudo make install
```

This builds a release binary and installs it to `/usr/local/bin`.

### Setup Claude Code skill

After installing the binary:

```bash
macp install-skill
```

This creates a skill file at `~/.claude/skills/macp/` that teaches Claude Code when and how to use `macp`.

### Permissions

`macp` needs two macOS permissions. Grant them to your **terminal app** (Terminal, iTerm, kitty, etc.) in **System Settings > Privacy & Security**:

1. **Accessibility** — for UI inspection and interaction
2. **Screen Recording** — for screenshots

Verify with:
```bash
macp check-access
```

## Usage

### Quick start
```bash
macp list-apps                              # find your app's PID
macp ui-tree 1234 --compact                 # see UI structure
macp action 1234 press --title "Save"       # click a button
macp screenshot --pid 1234                  # take a screenshot
```

### All commands
```
Diagnostics     check-access
App lifecycle   list-apps  launch-app  activate-app  quit-app
Windows         window-list  focus-window (--index or --title)
UI inspection   ui-tree (--compact)  read-element  wait-for
UI interaction  action (press/set-value/set-focus/show-menu)  menu
Low-level       click  drag  scroll  move-mouse  type-text  key-press
Utilities       clipboard  screenshot
Setup           install-skill
```

Run `macp help <command>` for details on any command.

### Typical workflow

```bash
# 1. Find the app
macp list-apps
# PID: 1234 | MyApp | com.example.myapp [active]

# 2. Understand the UI
macp ui-tree 1234 --compact -d 3

# 3. Interact
macp action 1234 press --title "Calculate"

# 4. Wait for result
macp wait-for 1234 --title-contains "Result" --timeout 3

# 5. Verify
macp read-element 1234 --role AXStaticText --title-contains "Result"
macp screenshot --pid 1234
```

### Low-level input

All low-level input commands accept `--pid` to auto-activate the target app first:

```bash
macp click 500 300 --pid 1234              # click at coordinates
macp type-text "hello" --pid 1234          # type text
macp key-press 36 --cmd --pid 1234         # Cmd+Return
macp scroll 500 300 -200 --pid 1234        # scroll down
macp drag 100 200 400 200 --pid 1234       # drag
```

## How it works with Claude Code

After `macp install-skill`, Claude Code automatically knows how to use `macp` when it needs to debug or verify a Mac app. The skill teaches Claude the workflow, best practices, and troubleshooting steps.

No MCP server, no configuration files. Claude Code calls `macp` directly via its Bash tool.

## Uninstall

```bash
brew uninstall macp          # if installed via Homebrew
# or
sudo make uninstall          # if installed from source

rm -rf ~/.claude/skills/macp # remove Claude Code skill
```

## License

MIT
