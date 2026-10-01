import AppKit
import SwiftUI
@main struct Stress {
 @MainActor static func main() async {
  let app = NSApplication.shared
  app.setActivationPolicy(.accessory)
  let volume = SystemVolumeBridge(ready: { false }, action: { _ in }, monitoring: false)
  volume.enabled = false
  let remote = TVRemoteBridge()
  let model = RemoteController()
  let host = NSHostingController(rootView: SettingsView(model:model,volumeKeys:volume,tvRemote:remote))
  let window = NSWindow(contentViewController:host)
  window.setContentSize(NSSize(width:500,height:520))
  window.orderFront(nil)
  for i in 0..<2000 {
   volume.update()
   remote.configure(connection:0,paused:false)
   if i == 100 { window.orderOut(nil) }
   try? await Task.sleep(nanoseconds:10_000_000)
  }
  print("STRESS DONE pid=\(getpid())"); fflush(stdout)
  try? await Task.sleep(nanoseconds:60_000_000_000)
  withExtendedLifetime(window) {}
 }
}
