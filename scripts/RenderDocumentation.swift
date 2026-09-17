import AppKit
import SwiftUI

/// Offline UI examples only. Never starts device discovery or media-key monitoring.
@main @MainActor struct RenderDocumentation {
    static func main() {
        _ = NSApplication.shared
        let model = RemoteController()
        model.connections = [CECConnection(id: 1, name: "HDMI")]
        model.connection = 1
        model.devices = [CECDevice(address: 0, name: L("客厅电视"))]
        model.status = L("方向键移动 · Return 确认")
        model.records = []
        let keys = SystemVolumeBridge(ready: { false }, action: { _ in }, monitoring: false)
        keys.status = L("已接管 HDMI 输出的音量键和静音键")
        capture(RemoteView(model: model, volumeKeys: keys, openSettings: {}), name: "remote", size: NSSize(width: 320, height: 550))
        capture(SettingsView(model: model, volumeKeys: keys, tvRemote: TVRemoteBridge()), name: "settings", size: NSSize(width: 540, height: 740))
    }
    static func capture<V: View>(_ view: V, name: String, size: NSSize) {
        let host = NSHostingView(rootView: view.environment(\.colorScheme, .light).frame(width: size.width, height: size.height, alignment: .top).background(Color(nsColor: .windowBackgroundColor)))
        host.appearance = NSAppearance(named: .aqua)
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("Cannot render \(name)") }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "docs/images/\(name).png"))
    }
}
