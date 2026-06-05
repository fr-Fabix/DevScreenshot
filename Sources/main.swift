import Cocoa
import ApplicationServices
import ServiceManagement

/// Pixel sizes accepted by App Store Connect for Mac apps — all 16:10.
let PRESET_SIZES: [(w: Int, h: Int)] = [(2560, 1600), (2880, 1800), (1440, 900), (1280, 800)]

/// App Store screenshot pixel sizes for iPhone/iPad (both orientations) — used to flag simulator shots.
let SIM_VALID_SIZES: Set<String> = [
    "1242x2688", "2688x1242",   // 6.5"  (iPhone 11 Pro Max / Xs Max)
    "1284x2778", "2778x1284",   // 6.7"  (iPhone 12–14 Pro Max)
    "1290x2796", "2796x1290",   // 6.7"/6.9" (iPhone 15/16 Pro Max)
    "1320x2868", "2868x1320",   // 6.9"  (iPhone 16/17 Pro Max)
    "2048x2732", "2732x2048",   // iPad 12.9"
    "2064x2752", "2752x2064",   // iPad 13"
]

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private let defaults = UserDefaults.standard

    // MARK: - Persisted settings

    private var targetW: Int { let v = defaults.integer(forKey: "targetW"); return v == 0 ? 2560 : v }
    private var targetH: Int { let v = defaults.integer(forKey: "targetH"); return v == 0 ? 1600 : v }

    private var outDir: String {
        if let d = defaults.string(forKey: "outDir"), !d.isEmpty {
            return (d as NSString).expandingTildeInPath
        }
        return ("~/Desktop/DevScreenshot" as NSString).expandingTildeInPath
    }

    private var captureDelay: Double { defaults.double(forKey: "captureDelay") }   // default 0
    private var revealInFinder: Bool { defaults.bool(forKey: "revealInFinder") }   // default false
    private var copyToClipboard: Bool { defaults.bool(forKey: "copyToClipboard") } // default false
    private var playSound: Bool {
        defaults.object(forKey: "playSound") == nil ? true : defaults.bool(forKey: "playSound")
    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ note: Notification) {
        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let img = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "DevScreenshot") {
                img.isTemplate = true
                button.image = img
            } else {
                button.title = "📸"   // fallback so the item is never invisible
            }
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    // MARK: - Menu (rebuilt on every open → live app list and option states)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        header(menu, "Target size (pixels)")
        for (i, s) in PRESET_SIZES.enumerated() {
            let it = action("\(s.w) × \(s.h)", #selector(pickSize(_:)))
            it.tag = i
            it.state = (s.w == targetW && s.h == targetH) ? .on : .off
            menu.addItem(it)
        }
        let isCustom = !PRESET_SIZES.contains { $0.w == targetW && $0.h == targetH }
        let custom = action(isCustom ? "Custom: \(targetW) × \(targetH)" : "Custom…", #selector(setCustomSize))
        custom.state = isCustom ? .on : .off
        menu.addItem(custom)

        menu.addItem(.separator())
        header(menu, "Capture window")

        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && ($0.localizedName?.isEmpty == false) }
            .sorted { ($0.localizedName ?? "").localizedCaseInsensitiveCompare($1.localizedName ?? "") == .orderedAscending }
        if apps.isEmpty { header(menu, "  (no app with a window open)") }
        for app in apps {
            let it = action(app.localizedName ?? "—", #selector(shoot(_:)))
            it.representedObject = app
            if let icon = app.icon, let img = icon.copy() as? NSImage {
                img.size = NSSize(width: 18, height: 18)
                it.image = img
            }
            menu.addItem(it)
        }

        let sims = bootedSimulators()
        if !sims.isEmpty {
            menu.addItem(.separator())
            header(menu, "Capture iOS Simulator")
            for sim in sims {
                let it = action(sim.name, #selector(shootSimulator(_:)))
                it.representedObject = sim.udid
                menu.addItem(it)
            }
        }

        menu.addItem(.separator())

        let optionsItem = NSMenuItem(title: "Options", action: nil, keyEquivalent: "")
        let options = NSMenu()
        for (label, value) in [("No delay", 0.0), ("2 second delay", 2.0), ("5 second delay", 5.0)] {
            let d = action(label, #selector(setDelay(_:)))
            d.representedObject = value
            d.state = abs(captureDelay - value) < 0.01 ? .on : .off
            options.addItem(d)
        }
        options.addItem(.separator())
        options.addItem(check("Reveal in Finder after capture", #selector(toggleReveal), revealInFinder))
        options.addItem(check("Copy to clipboard", #selector(toggleClipboard), copyToClipboard))
        options.addItem(check("Play shutter sound", #selector(toggleSound), playSound))
        optionsItem.submenu = options
        menu.addItem(optionsItem)

        menu.addItem(action("Save location…", #selector(chooseLocation)))
        let loc = NSMenuItem(title: "  → \(prettyPath(outDir))", action: nil, keyEquivalent: "")
        loc.isEnabled = false
        menu.addItem(loc)

        menu.addItem(.separator())
        menu.addItem(check("Launch at login", #selector(toggleLaunchAtLogin), launchAtLogin))

        menu.addItem(.separator())
        menu.addItem(action("Open screenshots folder", #selector(openFolder)))
        menu.addItem(action("About DevScreenshot", #selector(showAbout)))
        let quit = NSMenuItem(title: "Quit DevScreenshot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    // MARK: - Menu builders

    private func action(_ title: String, _ sel: Selector) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        it.target = self
        return it
    }
    private func check(_ title: String, _ sel: Selector, _ on: Bool) -> NSMenuItem {
        let it = action(title, sel)
        it.state = on ? .on : .off
        return it
    }
    private func header(_ menu: NSMenu, _ title: String) {
        let it = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        it.isEnabled = false
        menu.addItem(it)
    }
    private func prettyPath(_ p: String) -> String {
        let home = NSHomeDirectory()
        return p.hasPrefix(home) ? "~" + String(p.dropFirst(home.count)) : p
    }

    // MARK: - Size actions

    @objc private func pickSize(_ sender: NSMenuItem) {
        let s = PRESET_SIZES[sender.tag]
        defaults.set(s.w, forKey: "targetW")
        defaults.set(s.h, forKey: "targetH")
    }

    @objc private func setCustomSize() {
        let a = NSAlert()
        a.messageText = "Custom target size"
        a.informativeText = "Enter pixels as WIDTH × HEIGHT (e.g. 2560 x 1600)."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = "\(targetW) x \(targetH)"
        a.accessoryView = field
        a.addButton(withTitle: "OK")
        a.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let nums = field.stringValue.split { !$0.isNumber }.compactMap { Int($0) }
        if nums.count == 2, nums[0] > 0, nums[1] > 0 {
            defaults.set(nums[0], forKey: "targetW")
            defaults.set(nums[1], forKey: "targetH")
        }
    }

    // MARK: - Option actions

    @objc private func setDelay(_ sender: NSMenuItem) {
        defaults.set(sender.representedObject as? Double ?? 0, forKey: "captureDelay")
    }
    @objc private func toggleReveal()    { defaults.set(!revealInFinder, forKey: "revealInFinder") }
    @objc private func toggleClipboard() { defaults.set(!copyToClipboard, forKey: "copyToClipboard") }
    @objc private func toggleSound()     { defaults.set(!playSound, forKey: "playSound") }

    @objc private func chooseLocation() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Folder"
        panel.directoryURL = URL(fileURLWithPath: outDir)
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            defaults.set(url.path, forKey: "outDir")
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    @objc private func openFolder() {
        NSWorkspace.shared.open(URL(fileURLWithPath: outDir))
    }

    // MARK: - Launch at login (SMAppService, macOS 13+)

    private var launchAtLogin: Bool {
        if #available(macOS 13.0, *) { return SMAppService.mainApp.status == .enabled }
        return false
    }
    @objc private func toggleLaunchAtLogin() {
        guard #available(macOS 13.0, *) else { return }
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            alert("Login item failed", error.localizedDescription)
        }
    }

    @objc private func showAbout() {
        alert("DevScreenshot",
              "Pixel-exact window screenshots for Mac App Store assets.\n\n" +
              "Pick a target size, then pick an app. The front window is resized to the matching point size so the capture lands on the exact required pixels, then trimmed to the last pixel.\n\n" +
              "MIT licensed.")
    }

    // MARK: - Capture

    @objc private func shoot(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? NSRunningApplication else { return }
        guard ensureAccessibility() else {
            alert("Accessibility permission needed",
                  "Enable \u{201C}DevScreenshot\u{201D} under System Settings \u{2192} Privacy & Security \u{2192} Accessibility, then try again.")
            return
        }
        app.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5 + captureDelay) { [weak self] in
            self?.capture(app: app)
        }
    }

    private func capture(app: NSRunningApplication) {
        // Retina backing scale: a 2560×1600 px target needs a 1280×800 pt window on a 2× display.
        let scale = Int(NSScreen.screens.first?.backingScaleFactor ?? 2)
        let winW = targetW / scale
        let winH = targetH / scale

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        guard let window = mainWindow(of: axApp) else {
            alert("No window", "\(app.localizedName ?? "The app") has no visible window.")
            return
        }

        setPoint(window, kAXPositionAttribute, CGPoint(x: 0, y: 25))
        setSize(window, kAXSizeAttribute, CGSize(width: winW, height: winH))
        usleep(450_000)

        // Read the real geometry back — the app may enforce a minimum size.
        let pos  = getPoint(window, kAXPositionAttribute) ?? CGPoint(x: 0, y: 25)
        let size = getSize(window, kAXSizeAttribute) ?? CGSize(width: winW, height: winH)
        let rx = Int(pos.x.rounded()), ry = Int(pos.y.rounded())
        let rw = Int(size.width.rounded()), rh = Int(size.height.rounded())

        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd_HH.mm.ss"
        let safeName = (app.localizedName ?? "App").replacingOccurrences(of: " ", with: "_")
        let path = "\(outDir)/\(safeName)_\(targetW)x\(targetH)_\(stamp.string(from: Date())).png"

        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

        var args: [String] = []
        if !playSound { args.append("-x") }          // -x: silence the shutter sound
        args.append("-R\(rx),\(ry),\(rw),\(rh)")     // capture the exact window rect
        args.append(path)
        _ = shell("/usr/sbin/screencapture", args)

        guard FileManager.default.fileExists(atPath: path) else {
            alert("Screen recording permission needed",
                  "Enable \u{201C}DevScreenshot\u{201D} under System Settings \u{2192} Privacy & Security \u{2192} Screen Recording, then quit and relaunch the app.")
            return
        }

        ensureExactSize(path)

        if copyToClipboard, let img = NSImage(contentsOfFile: path) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([img])
        }

        notify("\(safeName) — \(targetW)×\(targetH) saved")

        if revealInFinder {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        }
    }

    // MARK: - iOS Simulator capture

    /// Booted simulators via `simctl list devices booted -j`.
    private func bootedSimulators() -> [(name: String, udid: String)] {
        let out = shell("/usr/bin/xcrun", ["simctl", "list", "devices", "booted", "-j"])
        guard let data = out.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let runtimes = json["devices"] as? [String: Any] else { return [] }
        var result: [(name: String, udid: String)] = []
        for (_, list) in runtimes {
            guard let devices = list as? [[String: Any]] else { continue }
            for d in devices where (d["state"] as? String) == "Booted" {
                if let name = d["name"] as? String, let udid = d["udid"] as? String {
                    result.append((name, udid))
                }
            }
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    @objc private func shootSimulator(_ sender: NSMenuItem) {
        guard let udid = sender.representedObject as? String else { return }
        let name = sender.title
        let stamp = DateFormatter(); stamp.dateFormat = "yyyy-MM-dd_HH.mm.ss"
        let safe = name.replacingOccurrences(of: " ", with: "_")
        let path = "\(outDir)/\(safe)_\(stamp.string(from: Date())).png"
        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

        // simctl captures at the device's native pixel resolution — already App-Store-exact, no resize.
        let result = shell("/usr/bin/xcrun", ["simctl", "io", udid, "screenshot", path])
        guard FileManager.default.fileExists(atPath: path) else {
            alert("Simulator capture failed", result.isEmpty ? "Could not capture \(name)." : result)
            return
        }

        let pw = pixelDimension(path, "pixelWidth")
        let ph = pixelDimension(path, "pixelHeight")
        let valid = SIM_VALID_SIZES.contains("\(pw)x\(ph)")

        if copyToClipboard, let img = NSImage(contentsOfFile: path) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([img])
        }
        notify("\(safe) — \(pw)×\(ph)\(valid ? " ✓ App Store" : " — not an App Store size")")
        if revealInFinder {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        }
    }

    // MARK: - Accessibility helpers

    private func mainWindow(of axApp: AXUIElement) -> AXUIElement? {
        var ref: CFTypeRef?
        if AXUIElementCopyAttributeValue(axApp, kAXMainWindowAttribute as CFString, &ref) == .success, let r = ref {
            return (r as! AXUIElement)
        }
        var windowsRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let arr = windowsRef as? [AXUIElement], let first = arr.first {
            return first
        }
        return nil
    }
    private func setPoint(_ el: AXUIElement, _ attr: String, _ value: CGPoint) {
        var v = value
        if let ax = AXValueCreate(.cgPoint, &v) { AXUIElementSetAttributeValue(el, attr as CFString, ax) }
    }
    private func setSize(_ el: AXUIElement, _ attr: String, _ value: CGSize) {
        var v = value
        if let ax = AXValueCreate(.cgSize, &v) { AXUIElementSetAttributeValue(el, attr as CFString, ax) }
    }
    private func getPoint(_ el: AXUIElement, _ attr: String) -> CGPoint? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &ref) == .success, let r = ref else { return nil }
        var p = CGPoint.zero
        AXValueGetValue(r as! AXValue, .cgPoint, &p)
        return p
    }
    private func getSize(_ el: AXUIElement, _ attr: String) -> CGSize? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &ref) == .success, let r = ref else { return nil }
        var s = CGSize.zero
        AXValueGetValue(r as! AXValue, .cgSize, &s)
        return s
    }

    // MARK: - Utilities

    private func ensureAccessibility() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private func pixelDimension(_ path: String, _ key: String) -> Int {
        let out = shell("/usr/bin/sips", ["-g", key, path])
        let last = out.split { $0 == " " || $0 == "\n" }.last.map(String.init) ?? ""
        return Int(last) ?? 0
    }

    /// Guarantee exact pixel dimensions without distortion: pad if smaller, crop if larger.
    private func ensureExactSize(_ path: String) {
        let pw = pixelDimension(path, "pixelWidth")
        let ph = pixelDimension(path, "pixelHeight")
        if pw == targetW && ph == targetH { return }
        if pw <= targetW && ph <= targetH {
            _ = shell("/usr/bin/sips", ["-p", "\(targetH)", "\(targetW)", path])   // pad, centered
        } else {
            _ = shell("/usr/bin/sips", ["-c", "\(targetH)", "\(targetW)", path])   // crop, centered
        }
    }

    @discardableResult
    private func shell(_ launchPath: String, _ args: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return "" }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func notify(_ text: String) {
        let safe = text.replacingOccurrences(of: "\"", with: "")
        _ = shell("/usr/bin/osascript", ["-e", "display notification \"\(safe)\" with title \"DevScreenshot\""])
    }

    private func alert(_ title: String, _ message: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = message
        a.alertStyle = .informational
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // menu-bar only, no Dock icon
app.run()
