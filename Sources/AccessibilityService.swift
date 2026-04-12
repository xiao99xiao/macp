import ApplicationServices
import AppKit

/// Wraps macOS Accessibility APIs (AXUIElement) for UI introspection and interaction.
final class AccessibilityService {

    static let shared = AccessibilityService()

    // MARK: - App Listing

    struct AppInfo {
        let pid: pid_t
        let name: String
        let bundleId: String?
        let isActive: Bool
    }

    func listRunningApps() -> [AppInfo] {
        let workspace = NSWorkspace.shared
        return workspace.runningApplications
            .filter { $0.activationPolicy == .regular }  // GUI apps only
            .map { app in
                AppInfo(
                    pid: app.processIdentifier,
                    name: app.localizedName ?? "Unknown",
                    bundleId: app.bundleIdentifier,
                    isActive: app.isActive
                )
            }
    }

    // MARK: - App Lifecycle

    struct LaunchResult {
        let success: Bool
        let pid: pid_t?
    }

    func launchApp(bundleId: String) -> LaunchResult {
        let config = NSWorkspace.OpenConfiguration()
        var resultApp: NSRunningApplication?
        var resultError: Error?
        let semaphore = DispatchSemaphore(value: 0)

        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            return LaunchResult(success: false, pid: nil)
        }

        NSWorkspace.shared.openApplication(at: url, configuration: config) { app, error in
            resultApp = app
            resultError = error
            semaphore.signal()
        }
        semaphore.wait()

        if let app = resultApp {
            return LaunchResult(success: true, pid: app.processIdentifier)
        }
        // App might already be running
        if resultError != nil {
            if let running = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleId }) {
                return LaunchResult(success: true, pid: running.processIdentifier)
            }
        }
        return LaunchResult(success: false, pid: nil)
    }

    func activateApp(pid: pid_t) -> Bool {
        if let app = NSRunningApplication(processIdentifier: pid) {
            return app.activate()
        }
        return false
    }

    /// Activate app and wait briefly for it to become frontmost
    func ensureForeground(pid: pid_t) {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        if app.isActive { return }
        app.activate()
        // Wait up to 500ms for app to become active
        for _ in 0..<10 {
            if app.isActive { return }
            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    func quitApp(pid: pid_t) -> Bool {
        if let app = NSRunningApplication(processIdentifier: pid) {
            return app.terminate()
        }
        return false
    }

    // MARK: - UI Element Tree

    func uiTree(pid: pid_t, maxDepth: Int = 5, compact: Bool = false) -> [String: Any] {
        let appElement = AXUIElementCreateApplication(pid)
        if compact {
            return describeElementCompact(appElement, depth: 0, maxDepth: maxDepth)
        }
        return describeElement(appElement, depth: 0, maxDepth: maxDepth)
    }

    /// Compact tree: only role + title/identifier/value (one line per node, much smaller)
    private func describeElementCompact(_ element: AXUIElement, depth: Int, maxDepth: Int) -> [String: Any] {
        var result: [String: Any] = [:]
        if let role = getStringAttribute(element, kAXRoleAttribute) { result["role"] = role }
        if let title = getStringAttribute(element, kAXTitleAttribute), !title.isEmpty { result["title"] = title }
        if let identifier = getStringAttribute(element, kAXIdentifierAttribute), !identifier.isEmpty { result["id"] = identifier }
        // Only include value for leaf-ish elements (text fields, etc.)
        let role = getStringAttribute(element, kAXRoleAttribute) ?? ""
        if ["AXTextField", "AXTextArea", "AXStaticText", "AXCheckBox", "AXRadioButton",
            "AXSlider", "AXComboBox", "AXPopUpButton", "AXValueIndicator"].contains(role) {
            if let value = getStringAttribute(element, kAXValueAttribute) { result["value"] = value }
        }
        if let enabled = getBoolAttribute(element, kAXEnabledAttribute), !enabled { result["enabled"] = false }

        if depth < maxDepth {
            var childrenRef: CFTypeRef?
            let childErr = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
            if childErr == .success, let children = childrenRef as? [AXUIElement], !children.isEmpty {
                result["children"] = children.map { describeElementCompact($0, depth: depth + 1, maxDepth: maxDepth) }
            }
        }
        return result
    }

    private func describeElement(_ element: AXUIElement, depth: Int, maxDepth: Int) -> [String: Any] {
        var result: [String: Any] = [:]

        // Role
        if let role = getStringAttribute(element, kAXRoleAttribute) {
            result["role"] = role
        }

        // Role description
        if let roleDesc = getStringAttribute(element, kAXRoleDescriptionAttribute) {
            result["roleDescription"] = roleDesc
        }

        // Title
        if let title = getStringAttribute(element, kAXTitleAttribute), !title.isEmpty {
            result["title"] = title
        }

        // Value
        if let value = getStringAttribute(element, kAXValueAttribute) {
            result["value"] = value
        }

        // Description
        if let desc = getStringAttribute(element, kAXDescriptionAttribute), !desc.isEmpty {
            result["description"] = desc
        }

        // Label (accessibility label)
        if let label = getStringAttribute(element, kAXLabelValueAttribute) {
            result["label"] = label
        }

        // Identifier
        if let identifier = getStringAttribute(element, kAXIdentifierAttribute), !identifier.isEmpty {
            result["identifier"] = identifier
        }

        // Enabled
        if let enabled = getBoolAttribute(element, kAXEnabledAttribute) {
            result["enabled"] = enabled
        }

        // Focused
        if let focused = getBoolAttribute(element, kAXFocusedAttribute) {
            if focused { result["focused"] = true }
        }

        // Position & Size
        if let pos = getPointAttribute(element, kAXPositionAttribute),
           let size = getSizeAttribute(element, kAXSizeAttribute) {
            result["frame"] = [
                "x": Int(pos.x), "y": Int(pos.y),
                "width": Int(size.width), "height": Int(size.height)
            ]
        }

        // Children
        if depth < maxDepth {
            var childrenRef: CFTypeRef?
            let childErr = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
            if childErr == .success, let children = childrenRef as? [AXUIElement] {
                if !children.isEmpty {
                    result["children"] = children.map { child in
                        describeElement(child, depth: depth + 1, maxDepth: maxDepth)
                    }
                }
            }
        }

        return result
    }

    // MARK: - Find Element

    struct FindCriteria {
        var role: String?
        var title: String?
        var titleContains: String?
        var identifier: String?
        var value: String?
        var valueContains: String?

        var hasAnyCriterion: Bool {
            role != nil || title != nil || titleContains != nil || identifier != nil || value != nil || valueContains != nil
        }
    }

    func findElement(pid: pid_t, role: String? = nil, title: String? = nil, identifier: String? = nil, index: Int = 0) -> AXUIElement? {
        findElement(pid: pid, criteria: FindCriteria(role: role, title: title, identifier: identifier), index: index)
    }

    func findElement(pid: pid_t, criteria: FindCriteria, index: Int = 0) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(pid)
        var matches: [AXUIElement] = []
        findElements(in: appElement, criteria: criteria, matches: &matches, maxResults: index + 1)
        return index < matches.count ? matches[index] : nil
    }

    private func findElements(in element: AXUIElement, criteria: FindCriteria, matches: inout [AXUIElement], maxResults: Int) {
        if matches.count >= maxResults { return }

        if matchesCriteria(element, criteria: criteria) {
            matches.append(element)
        }

        if matches.count >= maxResults { return }

        var childrenRef: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
        if err == .success, let children = childrenRef as? [AXUIElement] {
            for child in children {
                findElements(in: child, criteria: criteria, matches: &matches, maxResults: maxResults)
                if matches.count >= maxResults { break }
            }
        }
    }

    private func matchesCriteria(_ element: AXUIElement, criteria: FindCriteria) -> Bool {
        guard criteria.hasAnyCriterion else { return false }

        if let role = criteria.role {
            guard getStringAttribute(element, kAXRoleAttribute) == role else { return false }
        }
        if let title = criteria.title {
            guard getStringAttribute(element, kAXTitleAttribute) == title else { return false }
        }
        if let sub = criteria.titleContains {
            guard let t = getStringAttribute(element, kAXTitleAttribute), t.localizedCaseInsensitiveContains(sub) else { return false }
        }
        if let identifier = criteria.identifier {
            guard getStringAttribute(element, kAXIdentifierAttribute) == identifier else { return false }
        }
        if let value = criteria.value {
            guard getStringAttribute(element, kAXValueAttribute) == value else { return false }
        }
        if let sub = criteria.valueContains {
            guard let v = getStringAttribute(element, kAXValueAttribute), v.localizedCaseInsensitiveContains(sub) else { return false }
        }
        return true
    }

    /// Get info about a single found element (without dumping entire tree)
    func elementInfo(_ element: AXUIElement) -> [String: Any] {
        return describeElement(element, depth: 0, maxDepth: 0)
    }

    // MARK: - Window Management

    struct WindowInfo {
        let title: String
        let index: Int
        let frame: CGRect?
        let isMain: Bool
        let isMinimized: Bool
    }

    func listWindows(pid: pid_t) -> [WindowInfo] {
        let appElement = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        guard err == .success, let windows = windowsRef as? [AXUIElement] else { return [] }

        var mainWindowRef: CFTypeRef?
        AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &mainWindowRef)

        return windows.enumerated().map { (index, window) in
            let title = getStringAttribute(window, kAXTitleAttribute) ?? ""
            let pos = getPointAttribute(window, kAXPositionAttribute)
            let size = getSizeAttribute(window, kAXSizeAttribute)
            let frame: CGRect? = (pos != nil && size != nil) ? CGRect(origin: pos!, size: size!) : nil
            let minimized = getBoolAttribute(window, kAXMinimizedAttribute) ?? false

            var isMain = false
            if let mainWin = mainWindowRef {
                isMain = CFEqual(window, mainWin as CFTypeRef)
            }

            return WindowInfo(title: title, index: index, frame: frame, isMain: isMain, isMinimized: minimized)
        }
    }

    func focusWindow(pid: pid_t, title: String) -> Bool {
        let appElement = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        guard err == .success, let windows = windowsRef as? [AXUIElement] else { return false }

        for window in windows {
            let winTitle = getStringAttribute(window, kAXTitleAttribute) ?? ""
            if winTitle == title || winTitle.localizedCaseInsensitiveContains(title) {
                AXUIElementSetAttributeValue(appElement, kAXMainWindowAttribute as CFString, window)
                AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                _ = activateApp(pid: pid)
                return true
            }
        }
        return false
    }

    func focusWindow(pid: pid_t, index: Int) -> Bool {
        let appElement = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        guard err == .success, let windows = windowsRef as? [AXUIElement], index < windows.count else { return false }

        let window = windows[index]
        AXUIElementSetAttributeValue(appElement, kAXMainWindowAttribute as CFString, window)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        _ = activateApp(pid: pid)
        return true
    }

    // MARK: - Menu Bar

    func getMenuBarItems(pid: pid_t) -> [[String: String]] {
        let appElement = AXUIElementCreateApplication(pid)
        var menuBarRef: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(appElement, kAXMenuBarAttribute as CFString, &menuBarRef)
        guard err == .success, let menuBar = menuBarRef else { return [] }

        var childrenRef: CFTypeRef?
        let childErr = AXUIElementCopyAttributeValue(menuBar as! AXUIElement, kAXChildrenAttribute as CFString, &childrenRef)
        guard childErr == .success, let items = childrenRef as? [AXUIElement] else { return [] }

        return items.enumerated().map { (i, item) in
            var info: [String: String] = ["index": "\(i)"]
            if let title = getStringAttribute(item, kAXTitleAttribute) { info["title"] = title }
            return info
        }
    }

    /// Click through a menu path like ["File", "Save As..."]
    func clickMenu(pid: pid_t, path: [String]) -> Bool {
        guard !path.isEmpty else { return false }

        let appElement = AXUIElementCreateApplication(pid)
        var menuBarRef: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(appElement, kAXMenuBarAttribute as CFString, &menuBarRef)
        guard err == .success, let menuBarRef else { return false }
        let menuBar = menuBarRef as! AXUIElement

        // Find the top-level menu bar item
        var currentMenu: AXUIElement = menuBar
        for (depth, menuTitle) in path.enumerated() {
            var childrenRef: CFTypeRef?
            let childErr = AXUIElementCopyAttributeValue(currentMenu, kAXChildrenAttribute as CFString, &childrenRef)
            guard childErr == .success, let children = childrenRef as? [AXUIElement] else { return false }

            var found = false
            for child in children {
                let title = getStringAttribute(child, kAXTitleAttribute) ?? ""
                let role = getStringAttribute(child, kAXRoleAttribute) ?? ""

                if title == menuTitle || title.localizedCaseInsensitiveContains(menuTitle) {
                    if depth == path.count - 1 {
                        // Last item in path — press it
                        return AXUIElementPerformAction(child, kAXPressAction as CFString) == .success
                    } else {
                        // Open submenu
                        AXUIElementPerformAction(child, kAXPressAction as CFString)
                        Thread.sleep(forTimeInterval: 0.1)
                        // Get the submenu
                        if role == "AXMenuBarItem" || role == "AXMenuItem" {
                            var submenuRef: CFTypeRef?
                            let subErr = AXUIElementCopyAttributeValue(child, kAXChildrenAttribute as CFString, &submenuRef)
                            if subErr == .success, let submenus = submenuRef as? [AXUIElement], let submenu = submenus.first {
                                currentMenu = submenu
                                found = true
                                break
                            }
                        }
                    }
                }
            }
            if !found && depth < path.count - 1 { return false }
        }
        return false
    }

    // MARK: - Clipboard

    static func readClipboard() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    static func writeClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: - Wait for Element

    func waitForElement(pid: pid_t, criteria: FindCriteria, timeout: TimeInterval = 5.0, pollInterval: TimeInterval = 0.3) -> AXUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let element = findElement(pid: pid, criteria: criteria) {
                return element
            }
            Thread.sleep(forTimeInterval: pollInterval)
        }
        return nil
    }

    // MARK: - Actions

    enum UIAction {
        case press
        case showMenu
        case setValue(String)
        case setFocus
    }

    func performAction(on element: AXUIElement, action: UIAction) -> Bool {
        switch action {
        case .press:
            return AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
        case .showMenu:
            return AXUIElementPerformAction(element, kAXShowMenuAction as CFString) == .success
        case .setValue(let value):
            return AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, value as CFTypeRef) == .success
        case .setFocus:
            return AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, true as CFTypeRef) == .success
        }
    }

    // MARK: - Keyboard & Mouse

    func typeText(_ text: String) {
        for char in text {
            let str = String(char)
            let source = CGEventSource(stateID: .hidSystemState)
            if let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) {
                let nsStr = str as NSString
                let uniChars = [UniChar](unsafeUninitializedCapacity: Int(nsStr.length)) { buffer, count in
                    nsStr.getCharacters(buffer.baseAddress!)
                    count = Int(nsStr.length)
                }
                event.keyboardSetUnicodeString(stringLength: uniChars.count, unicodeString: uniChars)
                event.post(tap: .cghidEventTap)

                if let upEvent = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                    upEvent.keyboardSetUnicodeString(stringLength: uniChars.count, unicodeString: uniChars)
                    upEvent.post(tap: .cghidEventTap)
                }
            }
        }
    }

    func click(at point: CGPoint) {
        let source = CGEventSource(stateID: .hidSystemState)
        if let mouseDown = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left) {
            mouseDown.post(tap: .cghidEventTap)
        }
        if let mouseUp = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) {
            mouseUp.post(tap: .cghidEventTap)
        }
    }

    func doubleClick(at point: CGPoint) {
        let source = CGEventSource(stateID: .hidSystemState)
        // First click
        if let down1 = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left) {
            down1.setIntegerValueField(.mouseEventClickState, value: 1)
            down1.post(tap: .cghidEventTap)
        }
        if let up1 = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) {
            up1.setIntegerValueField(.mouseEventClickState, value: 1)
            up1.post(tap: .cghidEventTap)
        }
        // Second click
        if let down2 = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left) {
            down2.setIntegerValueField(.mouseEventClickState, value: 2)
            down2.post(tap: .cghidEventTap)
        }
        if let up2 = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) {
            up2.setIntegerValueField(.mouseEventClickState, value: 2)
            up2.post(tap: .cghidEventTap)
        }
    }

    func rightClick(at point: CGPoint) {
        let source = CGEventSource(stateID: .hidSystemState)
        if let mouseDown = CGEvent(mouseEventSource: source, mouseType: .rightMouseDown, mouseCursorPosition: point, mouseButton: .right) {
            mouseDown.post(tap: .cghidEventTap)
        }
        if let mouseUp = CGEvent(mouseEventSource: source, mouseType: .rightMouseUp, mouseCursorPosition: point, mouseButton: .right) {
            mouseUp.post(tap: .cghidEventTap)
        }
    }

    func drag(from start: CGPoint, to end: CGPoint, duration: TimeInterval = 0.5) {
        let source = CGEventSource(stateID: .hidSystemState)
        let steps = max(Int(duration * 60), 10) // ~60fps
        let dx = (end.x - start.x) / CGFloat(steps)
        let dy = (end.y - start.y) / CGFloat(steps)
        let stepDelay = duration / Double(steps)

        // Mouse down at start
        if let mouseDown = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: start, mouseButton: .left) {
            mouseDown.post(tap: .cghidEventTap)
        }

        // Move in steps
        for i in 1...steps {
            let point = CGPoint(x: start.x + dx * CGFloat(i), y: start.y + dy * CGFloat(i))
            if let drag = CGEvent(mouseEventSource: source, mouseType: .leftMouseDragged, mouseCursorPosition: point, mouseButton: .left) {
                drag.post(tap: .cghidEventTap)
            }
            Thread.sleep(forTimeInterval: stepDelay)
        }

        // Mouse up at end
        if let mouseUp = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: end, mouseButton: .left) {
            mouseUp.post(tap: .cghidEventTap)
        }
    }

    func scroll(at point: CGPoint, deltaX: Int = 0, deltaY: Int) {
        // Move mouse to position first
        let source = CGEventSource(stateID: .hidSystemState)
        if let move = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) {
            move.post(tap: .cghidEventTap)
        }
        if let scrollEvent = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2, wheel1: Int32(deltaY), wheel2: Int32(deltaX), wheel3: 0) {
            scrollEvent.post(tap: .cghidEventTap)
        }
    }

    func moveMouse(to point: CGPoint) {
        let source = CGEventSource(stateID: .hidSystemState)
        if let move = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) {
            move.post(tap: .cghidEventTap)
        }
    }

    func keyPress(keyCode: CGKeyCode, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .hidSystemState)
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) {
            keyDown.flags = flags
            keyDown.post(tap: .cghidEventTap)
        }
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
            keyUp.flags = flags
            keyUp.post(tap: .cghidEventTap)
        }
    }

    /// Post keyboard event via cgAnnotatedSessionEventTap with PID targeting.
    /// Events go through the session-level event pipeline → NSApp sendEvent: →
    /// NSEvent.addLocalMonitorForEvents will see them.
    func keyPressToApp(pid: pid_t, keyCode: CGKeyCode, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .hidSystemState)
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) {
            keyDown.flags = flags
            keyDown.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(pid))
            keyDown.post(tap: .cgAnnotatedSessionEventTap)
        }
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
            keyUp.flags = flags
            keyUp.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(pid))
            keyUp.post(tap: .cgAnnotatedSessionEventTap)
        }
    }

    /// Type text into a specific app via session-level events with PID targeting.
    func typeTextToApp(pid: pid_t, text: String) {
        for char in text {
            let str = String(char)
            let source = CGEventSource(stateID: .hidSystemState)
            if let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) {
                let nsStr = str as NSString
                let uniChars = [UniChar](unsafeUninitializedCapacity: Int(nsStr.length)) { buffer, count in
                    nsStr.getCharacters(buffer.baseAddress!)
                    count = Int(nsStr.length)
                }
                event.keyboardSetUnicodeString(stringLength: uniChars.count, unicodeString: uniChars)
                event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(pid))
                event.post(tap: .cgAnnotatedSessionEventTap)

                if let upEvent = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                    upEvent.keyboardSetUnicodeString(stringLength: uniChars.count, unicodeString: uniChars)
                    upEvent.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(pid))
                    upEvent.post(tap: .cgAnnotatedSessionEventTap)
                }
            }
        }
    }

    // MARK: - Attribute Helpers

    private func getStringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard err == .success, let val = value else { return nil }
        if let str = val as? String { return str }
        if let num = val as? NSNumber { return num.stringValue }
        return nil
    }

    private func getBoolAttribute(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        if err == .success {
            if let num = value as? NSNumber {
                return num.boolValue
            }
        }
        return nil
    }

    private func getPointAttribute(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard err == .success, let val = value, CFGetTypeID(val) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        if AXValueGetValue(val as! AXValue, .cgPoint, &point) {
            return point
        }
        return nil
    }

    private func getSizeAttribute(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard err == .success, let val = value, CFGetTypeID(val) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        if AXValueGetValue(val as! AXValue, .cgSize, &size) {
            return size
        }
        return nil
    }

    // MARK: - Permission Check

    static var isAccessibilityEnabled: Bool {
        AXIsProcessTrusted()
    }

    static func promptForAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
