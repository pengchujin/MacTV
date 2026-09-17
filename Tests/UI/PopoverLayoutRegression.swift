import AppKit
import SwiftUI

@MainActor func runPopoverLayoutRegression(popover: NSPopover, model: RemoteController, button: NSStatusBarButton, show: () -> Void) async {
    var failures = [String]()
    func check(_ stage: String) {
        guard let window = popover.contentViewController?.view.window,
              let screen = button.window?.screen else { failures.append("\(stage): missing window"); return }
        print("anchor bounds=\(button.bounds) frame=\(button.frame) window=\(String(describing: button.window?.frame)) flipped=\(button.isFlipped) contentSize=\(popover.contentSize)")
        let frame = window.frame, safe = screen.visibleFrame
        let view = popover.contentViewController!.view
        let content = window.convertToScreen(view.convert(view.bounds, to: nil))
        // Window chrome includes the arrow/shadow at the menu bar. The content
        // must fit visibleFrame; the complete window must fit the physical screen.
        let valid = safe.contains(content) && screen.frame.contains(frame)
        print("\(stage): window=\(frame) content=\(content) visible=\(safe) within=\(valid)")
        if !valid { failures.append(stage) }
    }
    model.scanning = true; model.status = L("正在寻找电视…")
    try? await Task.sleep(for: .milliseconds(200))
    show()
    try? await Task.sleep(for: .milliseconds(600))
    check("loading")
    model.connection = 1
    model.connections = [CECConnection(id: 1, name: "HDMI")]
    model.devices = [CECDevice(address: 0, name: "布局测试电视")]
    model.scanning = false; model.status = L("已连接 · HDMI-CEC")
    try? await Task.sleep(for: .milliseconds(600))
    check("discovered while open")
    model.status = L("未收到新的状态回复；设备可能不支持此查询，或回复被系统接收")
    try? await Task.sleep(for: .milliseconds(600))
    check("multiline feedback")
    popover.performClose(nil)
    show()
    try? await Task.sleep(for: .milliseconds(600))
    check("reopened")
    let previousLargeText = UserDefaults.standard.bool(forKey: "largeText")
    UserDefaults.standard.set(true, forKey: "largeText")
    popover.performClose(nil)
    show()
    try? await Task.sleep(for: .milliseconds(600))
    check("large text reopened")
    UserDefaults.standard.set(previousLargeText, forKey: "largeText")
    print(failures.isEmpty ? "PASS: popover stays inside screen" : "FAIL: \(failures.joined(separator: ", "))")
    fflush(stdout)
    exit(failures.isEmpty ? 0 : 1)
}
