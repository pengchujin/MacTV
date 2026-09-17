import AppKit
import SwiftUI

@main @MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let model = RemoteController()
    private var item: NSStatusItem!
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?
    private var keyboardMonitor: Any?
    private var refreshTimer: Timer?
    private var workspaceObserver: NSObjectProtocol?
    private lazy var volumeKeys = SystemVolumeBridge(ready: { [weak self] in
        guard let self else { return false }
        return self.model.connections.count == 1 && !self.model.scanning && self.model.connection != 0 && self.model.devices.contains { $0.address == self.model.audioTarget }
    }, action: { [weak self] in self?.model.performMediaKey($0) })
    static func main() {
        let app = NSApplication.shared, delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let index = CommandLine.arguments.firstIndex(of: "--render"), CommandLine.arguments.count > index + 1 {
            render(to: CommandLine.arguments[index + 1]); NSApp.terminate(nil); return
        }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "appletvremote.gen4", accessibilityDescription: L("MacTV"))
        item.button?.image?.isTemplate = true
        item.button?.toolTip = L("MacTV · 点击打开，右键查看命令")
        item.button?.target = self; item.button?.action = #selector(toggle)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        popover.behavior = .transient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.popover.isShown,
                  !(NSApp.keyWindow?.firstResponder is NSTextView),
                  event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
            let keys: [UInt16: String] = [123: "left", 124: "right", 125: "down", 126: "up", 36: "select", 51: "back"]
            if let id = keys[event.keyCode] { self.model.perform(id); return nil }
            return event
        }
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.model.refresh() }
        }
        // Compare the registry only; do not keep issuing CEC queries while idle.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.model.busy else { return }
                if case .success(let response) = await self.model.call(["connections"]),
                   (response.connections ?? []).map(\.id) != self.model.connections.map(\.id) { self.model.refresh() }
            }
        }
        #if LAYOUT_TEST
        if CommandLine.arguments.contains("--layout-test") {
            Task { await runPopoverLayoutRegression(popover: popover, model: model, button: item.button!, show: { self.show() }) }
            return
        }
        #endif
        model.refresh()
        if CommandLine.arguments.contains("--show") { DispatchQueue.main.async { self.show() } }
    }
    @objc func toggle() {
        if NSApp.currentEvent?.type == .rightMouseUp { showMenu(); return }
        if popover.isShown { popover.performClose(nil) } else { show() }
    }
    @objc func show() {
        guard let button = item.button, let screen = button.window?.screen else { return }
        guard !popover.isShown else { return }
        let largeText = UserDefaults.standard.bool(forKey: "largeText")
        let size = NSSize(width: largeText ? 372 : 320,
                          height: min(largeText ? 620 : 550, screen.visibleFrame.height - 32))
        let content = ScrollView(.vertical) {
            RemoteView(model: model, volumeKeys: volumeKeys, openSettings: { [weak self] in self?.showSettings() })
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: size.width, height: size.height, alignment: .top)
        let controller = NSHostingController(rootView: content)
        // SwiftUI must not resize the popover's NSWindow behind AppKit's back:
        // AppKit positions using contentSize, which must match the hosting viewport.
        controller.sizingOptions = []
        controller.view.setFrameSize(size)
        controller.preferredContentSize = size
        popover.contentViewController = controller
        popover.contentSize = size
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
    @objc func showSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: SettingsView(model: model, volumeKeys: volumeKeys))
            let window = NSWindow(contentViewController: controller)
            window.title = L("MacTV 设置")
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 500, height: 650))
            window.center(); window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    func showMenu() {
        popover.performClose(nil)
        let menu = NSMenu(); menu.delegate = self; menu.autoenablesItems = false
        func add(_ title: String, _ action: Selector, key: String = "") {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
            entry.target = self; menu.addItem(entry)
        }
        add(L("打开遥控器"), #selector(show))
        menu.addItem(.separator())
        for group in [L("声音"), L("导航"), L("输入与频道"), L("电源")] {
            let entry = NSMenuItem(title: group, action: nil, keyEquivalent: ""), submenu = NSMenu()
            submenu.autoenablesItems = false
            for command in RemoteCommand.all where command.group == group {
                let action = NSMenuItem(title: command.title, action: #selector(runCommand(_:)), keyEquivalent: "")
                action.target = self; action.representedObject = command.id; action.isEnabled = model.ready
                submenu.addItem(action)
            }
            entry.submenu = submenu; menu.addItem(entry)
        }
        menu.addItem(.separator())
        add(L("重新检测电视"), #selector(refresh))
        add(L("设置…"), #selector(showSettings), key: ",")
        add(L("退出 MacTV"), #selector(quit), key: "q")
        item.menu = menu; item.button?.performClick(nil)
    }
    func menuDidClose(_ menu: NSMenu) { item.menu = nil }
    @objc func refresh() { model.refresh() }
    @objc func runCommand(_ item: NSMenuItem) { if let id = item.representedObject as? String { model.perform(id) } }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { show(); return true }
    // Explicit design fixtures only; normal launches always discover real hardware.
    private func render(to directory: String) {
        let fixture = RemoteController()
        fixture.connections = [CECConnection(id: 1, name: "HDMI")]
        fixture.connection = 1; fixture.devices = [CECDevice(address: 0, name: L("客厅电视"))]
        fixture.status = L("方向键移动 · Return 确认")
        let bridge = SystemVolumeBridge(ready: { false }, action: { _ in }, monitoring: false)
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let view = RemoteView(model: fixture, volumeKeys: bridge, openSettings: {})
                .environment(\.colorScheme, name == "dark" ? .dark : .light)
                .background(Color(nsColor: .windowBackgroundColor))
            let host = NSHostingView(rootView: view)
            host.appearance = NSAppearance(named: appearance)
            host.frame = NSRect(origin: .zero, size: host.fittingSize)
            host.layoutSubtreeIfNeeded()
            if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: directory).appendingPathComponent("remote-\(name).png"))
            }
        }
    }
}
