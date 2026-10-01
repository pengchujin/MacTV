import AppKit
import Combine

@main struct IdlePublicationRegression {
    @MainActor static func main() {
        let volume = SystemVolumeBridge(ready: { false }, action: { _ in }, monitoring: false)
        volume.enabled = false
        volume.update()
        let remote = TVRemoteBridge()
        remote.configure(connection: 0, paused: false)
        var volumeChanges = 0, remoteChanges = 0
        let a = volume.objectWillChange.sink { volumeChanges += 1 }
        let b = remote.objectWillChange.sink { remoteChanges += 1 }
        for _ in 0..<1000 {
            volume.update()
            remote.configure(connection: 0, paused: false)
        }
        print("Idle publications: volume=\(volumeChanges), remote=\(remoteChanges)")
        withExtendedLifetime((a, b)) {}
        guard volumeChanges == 0 && remoteChanges == 0 else { exit(1) }
        volume.needsPermission = true
        volume.status = "stale"
        let before = volumeChanges
        volume.update()
        guard !volume.needsPermission, volume.status != "stale", volumeChanges == before + 2 else { exit(1) }
        remote.status = "stale"
        let remoteBefore = remoteChanges
        remote.configure(connection: 0, paused: false)
        guard remote.status != "stale", remoteChanges == remoteBefore + 1 else { exit(1) }
        print("PASS: idle state is silent; changed state still publishes")
    }
}
