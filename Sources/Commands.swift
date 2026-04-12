import ArgumentParser
import Foundation
import AppKit

// MARK: - Diagnostics

struct CheckAccess: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "check-access",
        abstract: "Check if Accessibility and Screen Recording permissions are granted."
    )

    func run() {
        let ax = AccessibilityService.isAccessibilityEnabled
        let sr = ScreenCapture.shared.captureScreen() != nil

        print("Accessibility: \(ax ? "GRANTED" : "NOT GRANTED")")
        print("Screen Recording: \(sr ? "GRANTED" : "NOT GRANTED")")

        if !ax {
            print("\nGrant Accessibility in: System Settings > Privacy & Security > Accessibility")
        }
        if !sr {
            print("\nGrant Screen Recording in: System Settings > Privacy & Security > Screen Recording")
        }
    }
}

// MARK: - App Lifecycle

struct ListApps: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list-apps",
        abstract: "List running GUI applications."
    )

    func run() {
        let apps = AccessibilityService.shared.listRunningApps()
        for app in apps {
            let active = app.isActive ? " [active]" : ""
            let bid = app.bundleId ?? "n/a"
            print("PID: \(app.pid) | \(app.name) | \(bid)\(active)")
        }
    }
}

struct LaunchApp: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "launch-app",
        abstract: "Launch an app by bundle identifier."
    )

    @Argument(help: "Bundle identifier (e.g. com.apple.TextEdit)")
    var bundleId: String

    func run() throws {
        let result = AccessibilityService.shared.launchApp(bundleId: bundleId)
        if result.success {
            if let pid = result.pid {
                print("Launched \(bundleId) (PID: \(pid))")
            } else {
                print("Launched \(bundleId)")
            }
        } else {
            printError("Failed to launch \(bundleId)")
            throw ExitCode.failure
        }
    }
}

struct ActivateApp: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "activate-app",
        abstract: "Bring an app to the foreground."
    )

    @Argument(help: "Process ID")
    var pid: Int32

    func run() throws {
        guard AccessibilityService.shared.activateApp(pid: pid) else {
            printError("Failed to activate PID \(pid)")
            throw ExitCode.failure
        }
        print("Activated PID \(pid)")
    }
}

struct QuitApp: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "quit-app",
        abstract: "Quit an app."
    )

    @Argument(help: "Process ID")
    var pid: Int32

    func run() throws {
        guard AccessibilityService.shared.quitApp(pid: pid) else {
            printError("Failed to quit PID \(pid)")
            throw ExitCode.failure
        }
        print("Quit PID \(pid)")
    }
}

// MARK: - Window Management

struct WindowList: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "window-list",
        abstract: "List all windows of an app."
    )

    @Argument(help: "Process ID")
    var pid: Int32

    func run() {
        let windows = AccessibilityService.shared.listWindows(pid: pid)
        if windows.isEmpty {
            print("No windows found")
            return
        }
        for w in windows {
            var parts: [String] = ["[\(w.index)]", "\"\(w.title)\""]
            if w.isMain { parts.append("[main]") }
            if w.isMinimized { parts.append("[minimized]") }
            if let f = w.frame {
                parts.append("(\(Int(f.origin.x)),\(Int(f.origin.y)) \(Int(f.width))x\(Int(f.height)))")
            }
            print(parts.joined(separator: " "))
        }
    }
}

struct FocusWindow: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "focus-window",
        abstract: "Focus a window by index or title."
    )

    @Argument(help: "Process ID")
    var pid: Int32

    @Option(name: .shortAndLong, help: "Window index (from window-list)")
    var index: Int?

    @Option(name: .shortAndLong, help: "Window title (exact or substring match)")
    var title: String?

    func run() throws {
        if let title = title {
            guard AccessibilityService.shared.focusWindow(pid: pid, title: title) else {
                printError("No window matching title \"\(title)\"")
                throw ExitCode.failure
            }
            print("Focused window \"\(title)\"")
        } else if let index = index {
            guard AccessibilityService.shared.focusWindow(pid: pid, index: index) else {
                printError("Failed to focus window \(index)")
                throw ExitCode.failure
            }
            print("Focused window \(index)")
        } else {
            printError("Provide --index or --title")
            throw ExitCode.failure
        }
    }
}

// MARK: - UI Inspection

struct UITree: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ui-tree",
        abstract: "Get the accessibility UI element tree."
    )

    @Argument(help: "Process ID")
    var pid: Int32

    @Option(name: .shortAndLong, help: "Max tree depth (default: 5)")
    var depth: Int = 5

    @Flag(name: .shortAndLong, help: "Compact mode: only role/title/id/value")
    var compact: Bool = false

    func run() throws {
        guard AccessibilityService.isAccessibilityEnabled else {
            printError("Accessibility permission not granted.")
            throw ExitCode.failure
        }
        let tree = AccessibilityService.shared.uiTree(pid: pid, maxDepth: depth, compact: compact)
        if let data = try? JSONSerialization.data(withJSONObject: tree, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            print(str)
        }
    }
}

struct ReadElement: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "read-element",
        abstract: "Find a single UI element and return its full attributes (role, title, value, frame, enabled, focused)."
    )

    @Argument(help: "Process ID")
    var pid: Int32

    @Option(help: "AX role to match (e.g. AXButton, AXTextField)")
    var role: String?

    @Option(help: "Exact title to match")
    var title: String?

    @Option(name: .customLong("title-contains"), help: "Title substring (case-insensitive)")
    var titleContains: String?

    @Option(name: .customLong("id"), help: "Accessibility identifier")
    var identifier: String?

    @Option(name: .customLong("value-contains"), help: "Value substring (case-insensitive)")
    var valueContains: String?

    @Option(help: "Element index if multiple match (default: 0)")
    var index: Int = 0

    func run() throws {
        let criteria = AccessibilityService.FindCriteria(
            role: role, title: title, titleContains: titleContains,
            identifier: identifier, valueContains: valueContains
        )
        guard criteria.hasAnyCriterion else {
            printError("At least one search criterion required.")
            throw ExitCode.failure
        }

        guard let element = AccessibilityService.shared.findElement(
            pid: pid, criteria: criteria, index: index
        ) else {
            printError("Element not found")
            throw ExitCode.failure
        }

        let info = AccessibilityService.shared.elementInfo(element)
        if let data = try? JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            print(str)
        }
    }
}

struct WaitFor: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "wait-for",
        abstract: "Wait for a UI element to appear."
    )

    @Argument(help: "Process ID")
    var pid: Int32

    @Option(help: "AX role to match (e.g. AXButton, AXSheet)")
    var role: String?

    @Option(help: "Exact title to match")
    var title: String?

    @Option(name: .customLong("title-contains"), help: "Title substring (case-insensitive)")
    var titleContains: String?

    @Option(name: .customLong("id"), help: "Accessibility identifier")
    var identifier: String?

    @Option(name: .shortAndLong, help: "Timeout in seconds (default: 5)")
    var timeout: Double = 5.0

    func run() throws {
        let criteria = AccessibilityService.FindCriteria(
            role: role, title: title, titleContains: titleContains, identifier: identifier
        )
        guard criteria.hasAnyCriterion else {
            printError("At least one search criterion required.")
            throw ExitCode.failure
        }

        if let element = AccessibilityService.shared.waitForElement(
            pid: pid, criteria: criteria, timeout: timeout
        ) {
            let info = AccessibilityService.shared.elementInfo(element)
            if let data = try? JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys]),
               let str = String(data: data, encoding: .utf8) {
                print(str)
            }
        } else {
            printError("Element not found within \(timeout)s")
            throw ExitCode.failure
        }
    }
}

// MARK: - UI Interaction

struct Action: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "action",
        abstract: "Perform an action on a UI element (press, set-value, set-focus, show-menu)."
    )

    @Argument(help: "Process ID")
    var pid: Int32

    @Argument(help: "Action: press, set-value, set-focus, show-menu")
    var actionName: String

    @Option(help: "AX role to match")
    var role: String?

    @Option(help: "Exact title to match")
    var title: String?

    @Option(name: .customLong("title-contains"), help: "Title substring (case-insensitive)")
    var titleContains: String?

    @Option(name: .customLong("id"), help: "Accessibility identifier")
    var identifier: String?

    @Option(help: "Value to set (for set-value)")
    var value: String?

    @Option(help: "Element index if multiple match (default: 0)")
    var index: Int = 0

    func run() throws {
        let criteria = AccessibilityService.FindCriteria(
            role: role, title: title, titleContains: titleContains, identifier: identifier
        )
        guard criteria.hasAnyCriterion else {
            printError("At least one search criterion required.")
            throw ExitCode.failure
        }

        guard let element = AccessibilityService.shared.findElement(
            pid: pid, criteria: criteria, index: index
        ) else {
            printError("Element not found")
            throw ExitCode.failure
        }

        let action: AccessibilityService.UIAction
        switch actionName {
        case "press": action = .press
        case "show-menu": action = .showMenu
        case "set-focus": action = .setFocus
        case "set-value":
            guard let v = value else {
                printError("--value required for set-value action")
                throw ExitCode.failure
            }
            action = .setValue(v)
        default:
            printError("Unknown action: \(actionName). Use: press, set-value, set-focus, show-menu")
            throw ExitCode.failure
        }

        guard AccessibilityService.shared.performAction(on: element, action: action) else {
            printError("Action failed")
            throw ExitCode.failure
        }

        // Report what was acted on
        let info = AccessibilityService.shared.elementInfo(element)
        var desc: [String] = []
        if let r = info["role"] as? String { desc.append(r) }
        if let t = info["title"] as? String, !t.isEmpty { desc.append("\"\(t)\"") }
        if let i = info["identifier"] as? String, !i.isEmpty { desc.append("id=\(i)") }
        if let f = info["frame"] as? [String: Any] {
            let x = f["x"] as? Int ?? 0, y = f["y"] as? Int ?? 0
            let w = f["width"] as? Int ?? 0, h = f["height"] as? Int ?? 0
            desc.append("at (\(x),\(y) \(w)x\(h))")
        }
        print("\(actionName): \(desc.joined(separator: " "))")
    }
}

struct Menu: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "menu",
        abstract: "List menu bar items or click a menu path."
    )

    @Argument(help: "Process ID")
    var pid: Int32

    @Argument(help: "Menu path (e.g. File \"Save As...\")")
    var path: [String] = []

    func run() throws {
        if path.isEmpty {
            let items = AccessibilityService.shared.getMenuBarItems(pid: pid)
            if items.isEmpty {
                printError("No menu bar found")
                throw ExitCode.failure
            }
            for item in items {
                let title = item["title"] ?? "?"
                let index = item["index"] ?? "?"
                print("[\(index)] \(title)")
            }
        } else {
            guard AccessibilityService.shared.clickMenu(pid: pid, path: path) else {
                printError("Menu path not found: \(path.joined(separator: " > "))")
                throw ExitCode.failure
            }
            print("Clicked: \(path.joined(separator: " > "))")
        }
    }
}

// MARK: - Low-level Input
// All input commands accept --pid to auto-activate the target app before input.

struct Click: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "click",
        abstract: "Click at screen coordinates."
    )

    @Argument(help: "X coordinate")
    var x: Int

    @Argument(help: "Y coordinate")
    var y: Int

    @Option(name: .shortAndLong, help: "Button: left (default), right, double")
    var button: String = "left"

    @Option(name: .shortAndLong, help: "Target app PID (auto-activates before click)")
    var pid: Int32?

    func run() {
        if let pid = pid { AccessibilityService.shared.ensureForeground(pid: pid) }
        let point = CGPoint(x: x, y: y)
        switch button {
        case "right":
            AccessibilityService.shared.rightClick(at: point)
            print("Right-clicked (\(x), \(y))")
        case "double":
            AccessibilityService.shared.doubleClick(at: point)
            print("Double-clicked (\(x), \(y))")
        default:
            AccessibilityService.shared.click(at: point)
            print("Clicked (\(x), \(y))")
        }
    }
}

struct Drag: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "drag",
        abstract: "Drag from one point to another."
    )

    @Argument(help: "Start X")
    var fromX: Int

    @Argument(help: "Start Y")
    var fromY: Int

    @Argument(help: "End X")
    var toX: Int

    @Argument(help: "End Y")
    var toY: Int

    @Option(name: .shortAndLong, help: "Duration in seconds (default: 0.5)")
    var duration: Double = 0.5

    @Option(name: .shortAndLong, help: "Target app PID (auto-activates before drag)")
    var pid: Int32?

    func run() {
        if let pid = pid { AccessibilityService.shared.ensureForeground(pid: pid) }
        AccessibilityService.shared.drag(
            from: CGPoint(x: fromX, y: fromY),
            to: CGPoint(x: toX, y: toY),
            duration: duration
        )
        print("Dragged (\(fromX),\(fromY)) → (\(toX),\(toY))")
    }
}

struct Scroll: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scroll",
        abstract: "Scroll at a position."
    )

    @Argument(help: "X coordinate")
    var x: Int

    @Argument(help: "Y coordinate")
    var y: Int

    @Argument(help: "Vertical delta (positive=up, negative=down)")
    var deltaY: Int

    @Option(name: .customLong("dx"), help: "Horizontal delta (default: 0)")
    var deltaX: Int = 0

    @Option(name: .shortAndLong, help: "Target app PID (auto-activates before scroll)")
    var pid: Int32?

    func run() {
        if let pid = pid { AccessibilityService.shared.ensureForeground(pid: pid) }
        AccessibilityService.shared.scroll(at: CGPoint(x: x, y: y), deltaX: deltaX, deltaY: deltaY)
        print("Scrolled at (\(x),\(y)) dy=\(deltaY) dx=\(deltaX)")
    }
}

struct MoveMouse: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "move-mouse",
        abstract: "Move mouse cursor without clicking."
    )

    @Argument(help: "X coordinate")
    var x: Int

    @Argument(help: "Y coordinate")
    var y: Int

    func run() {
        AccessibilityService.shared.moveMouse(to: CGPoint(x: x, y: y))
        print("Moved to (\(x), \(y))")
    }
}

struct TypeText: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "type-text",
        abstract: "Type text via keyboard events into the focused field."
    )

    @Argument(help: "Text to type")
    var text: String

    @Option(name: .shortAndLong, help: "Target app PID — delivers events via AX API (goes through NSApp event loop)")
    var pid: Int32?

    func run() {
        if let pid = pid {
            AccessibilityService.shared.ensureForeground(pid: pid)
            AccessibilityService.shared.typeTextToApp(pid: pid, text: text)
        } else {
            AccessibilityService.shared.typeText(text)
        }
        print("Typed \(text.count) characters")
    }
}

struct KeyPress: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "key-press",
        abstract: "Send a key press. Common codes: Return=36 Tab=48 Space=49 Delete=51 Escape=53 ←=123 →=124 ↓=125 ↑=126 A=0 S=1 C=8 V=9 Q=12 W=13"
    )

    @Argument(help: "Virtual key code")
    var keyCode: UInt16

    @Flag(name: .customLong("cmd"), help: "Command modifier")
    var command: Bool = false

    @Flag(name: .customLong("shift"), help: "Shift modifier")
    var shift: Bool = false

    @Flag(name: .customLong("opt"), help: "Option modifier")
    var option: Bool = false

    @Flag(name: .customLong("ctrl"), help: "Control modifier")
    var control: Bool = false

    @Option(name: .shortAndLong, help: "Target app PID — delivers events via AX API (goes through NSApp event loop)")
    var pid: Int32?

    func run() {
        var flags = CGEventFlags()
        if command { flags.insert(.maskCommand) }
        if shift { flags.insert(.maskShift) }
        if option { flags.insert(.maskAlternate) }
        if control { flags.insert(.maskControl) }

        if let pid = pid {
            AccessibilityService.shared.ensureForeground(pid: pid)
            AccessibilityService.shared.keyPressToApp(pid: pid, keyCode: CGKeyCode(keyCode), flags: flags)
        } else {
            AccessibilityService.shared.keyPress(keyCode: CGKeyCode(keyCode), flags: flags)
        }
        print("Key \(keyCode) sent")
    }
}

// MARK: - Utilities

struct Clipboard: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clipboard",
        abstract: "Read or write the system clipboard."
    )

    @Argument(help: "Action: read or write")
    var action: String

    @Argument(help: "Text to write (for write action)")
    var text: String?

    func run() throws {
        switch action {
        case "read":
            if let content = AccessibilityService.readClipboard() {
                print(content)
            } else {
                print("(empty or non-text)")
            }
        case "write":
            guard let text = text else {
                printError("Text argument required for write")
                throw ExitCode.failure
            }
            AccessibilityService.writeClipboard(text)
            print("Written \(text.count) characters")
        default:
            printError("Unknown action: \(action). Use: read, write")
            throw ExitCode.failure
        }
    }
}

struct Screenshot: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "screenshot",
        abstract: "Capture a screenshot and save to file."
    )

    @Option(help: "Capture only this app's window (by PID)")
    var pid: Int32?

    @Option(help: "Region X")
    var x: Int?

    @Option(help: "Region Y")
    var y: Int?

    @Option(help: "Region width")
    var width: Int?

    @Option(help: "Region height")
    var height: Int?

    @Option(name: .shortAndLong, help: "Output file path (default: /tmp/macp_screenshot.png)")
    var output: String = "/tmp/macp_screenshot.png"

    func run() throws {
        let base64: String?

        if let pid = pid {
            base64 = ScreenCapture.shared.captureWindow(pid: pid)
        } else if let x = x, let y = y, let w = width, let h = height {
            base64 = ScreenCapture.shared.captureRegion(x: x, y: y, width: w, height: h)
        } else {
            base64 = ScreenCapture.shared.captureScreen()
        }

        guard let b64 = base64, let data = Data(base64Encoded: b64) else {
            printError("Failed to capture screenshot. Check Screen Recording permission.")
            throw ExitCode.failure
        }

        let url = URL(fileURLWithPath: output)
        try data.write(to: url)
        print(url.path)
    }
}

// MARK: - Install Skill

struct InstallSkill: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install-skill",
        abstract: "Install the macp skill for Claude Code."
    )

    func run() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let skillDir = "\(home)/.claude/skills/macp"
        let skillFile = "\(skillDir)/SKILL.md"

        try FileManager.default.createDirectory(atPath: skillDir, withIntermediateDirectories: true)
        try skillContent.write(toFile: skillFile, atomically: true, encoding: .utf8)
        print("Installed skill to \(skillFile)")
        print("Restart Claude Code to activate.")
    }
}

private let skillContent = ##"""
---
name: macp
description: Operate and debug running macOS apps — inspect UI, interact with elements, take screenshots to visually verify behavior. Use when you need to verify a Mac app works as expected after building, or when debugging UI issues that can't be caught by compilation alone.
---

# macp — Mac App Control Protocol

Use the `macp` CLI tool (via Bash) to interact with running macOS applications. This solves the core gap: you can compile code, but you can't see or interact with the running app — until now.

## When to Use

- After building a Mac/iOS app, to verify the UI looks and behaves correctly
- When debugging a visual or interaction bug you can't reproduce from code alone
- When the user asks you to "check if it works", "try clicking X", "see what happens when..."
- When testing menu items, keyboard shortcuts, or multi-step UI flows

## Core Workflow

### 1. Find the target app
```bash
macp list-apps
```
Output: `PID: 1234 | MyApp | com.example.myapp [active]`

### 2. Understand the UI structure
```bash
macp ui-tree 1234 --compact          # compact: role/title/id only (use this first!)
macp ui-tree 1234 --compact -d 3     # limit depth for large apps
macp ui-tree 1234                     # full: includes frames, values, descriptions
```

### 3. Query a specific element
```bash
macp read-element 1234 --role AXButton --title "Save"
macp read-element 1234 --role AXTextField --id "nameField"
macp read-element 1234 --title-contains "Status"
```
Returns full attributes including frame (position+size), value, enabled state. Use this to:
- **Verify state**: check a label's value, a checkbox's state, a button's enabled status
- **Get coordinates**: when you need to click by position, read the frame first

### 4. Interact with the app

**Semantic (preferred — finds elements by role/title/id):**
```bash
macp action 1234 press --title "Save"
macp action 1234 press --role AXButton --title-contains "OK"
macp action 1234 set-value --role AXTextField --id "nameField" --value "hello"
macp action 1234 set-focus --role AXTextArea --index 0
macp menu 1234 File "Save As..."       # click through menu path
macp menu 1234                          # list top-level menus first
```
`action` reports what it found: `press: AXButton "Save" id=saveBtn at (200,300 80x24)`

**Low-level (use --pid to auto-activate the target app):**
```bash
macp click 500 300 --pid 1234           # left click, app auto-activated first
macp click 500 300 -b right --pid 1234  # right click
macp click 500 300 -b double --pid 1234 # double click
macp drag 100 200 400 200 --pid 1234    # drag
macp scroll 500 300 -100 --pid 1234     # scroll down
macp type-text "Hello World" --pid 1234 # type into focused field
macp key-press 36 --pid 1234            # Return
macp key-press 0 --cmd --pid 1234       # Cmd+A
```
**Always pass `--pid`** for low-level input commands to ensure the target app is frontmost.

### 5. Wait for UI changes
After an action that triggers animation/loading/navigation:
```bash
macp wait-for 1234 --role AXSheet --timeout 3
macp wait-for 1234 --title-contains "Success"
```

### 6. Visually verify
```bash
macp screenshot --pid 1234              # capture app window → /tmp/macp_screenshot.png
macp screenshot -o /tmp/after.png       # custom path
```
Then use the **Read** tool to view the image file.

## Window Management
```bash
macp window-list 1234                   # list all windows
macp focus-window 1234 --title "Prefs"  # focus by title (preferred, stable)
macp focus-window 1234 --index 0        # focus by index
```

## Clipboard
```bash
macp clipboard read
macp clipboard write "test data"
```

## Common Patterns

**Type into a specific field:**
```bash
macp action 1234 set-focus --role AXTextField --id "searchField"
macp type-text "query" --pid 1234
```

**Click a button that has no title (icon-only):**
```bash
macp read-element 1234 --role AXButton --index 2    # get frame
macp click 240 312 --pid 1234                        # use the coordinates from frame
```

**Verify a value changed:**
```bash
macp action 1234 press --title "Calculate"
macp wait-for 1234 --role AXStaticText --title-contains "Result"
macp read-element 1234 --role AXStaticText --title-contains "Result"
```

## Key Codes Reference
Return=36, Tab=48, Space=49, Delete=51, Escape=53,
←=123, →=124, ↓=125, ↑=126,
A=0, S=1, D=2, F=3, H=4, G=5, Z=6, X=7, C=8, V=9, N=45, M=46, Q=12, W=13, E=14, R=15, T=17

## Troubleshooting

- **"Accessibility permission not granted"** → System Settings > Privacy & Security > Accessibility
- **"Failed to capture screenshot"** → System Settings > Privacy & Security > Screen Recording
- **Element not found** → Use `macp ui-tree PID --compact` to see available elements. Try `--title-contains` for fuzzy match.
- **Input goes to wrong app** → Always use `--pid` with low-level input commands
- **Large app tree** → Use `--compact -d 3` to limit output; pipe through `| head -80`
"""##

// MARK: - Helpers

func printError(_ message: String) {
    FileHandle.standardError.write(Data("Error: \(message)\n".utf8))
}
