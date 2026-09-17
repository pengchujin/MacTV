import AppKit
import CoreAudio

@MainActor final class TVRemoteBridge: ObservableObject {
    @Published var enabled = UserDefaults.standard.bool(forKey: "tvRemoteControlsMac") {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "tvRemoteControlsMac")
            configure(connection: connection, paused: paused)
        }
    }
    @Published var mapSelect = UserDefaults.standard.bool(forKey: "tvRemoteSelectTogglesPlayback") {
        didSet { UserDefaults.standard.set(mapSelect, forKey: "tvRemoteSelectTogglesPlayback") }
    }
    @Published var mapNavigation = UserDefaults.standard.bool(forKey: "tvRemoteNavigationControlsMedia") {
        didSet { UserDefaults.standard.set(mapNavigation, forKey: "tvRemoteNavigationControlsMedia") }
    }
    @Published var status = L("电视遥控器控制已关闭")
    @Published var lastReceived = ""
    private var task: Task<Void, Never>?
    private var connection: UInt64 = 0
    private var activeConnection: UInt64 = 0
    private var paused = false
    private var generation = UUID()

    func configure(connection: UInt64, paused: Bool) {
        self.connection = connection; self.paused = paused
        let desired = enabled && !paused ? connection : 0
        guard desired != activeConnection || (desired != 0 && task == nil) else {
            if desired == 0 { status = enabled ? L("等待 HDMI 连接空闲") : L("电视遥控器控制已关闭") }
            return
        }
        task?.cancel(); task = nil; activeConnection = desired
        generation = UUID()
        guard desired != 0 else {
            status = enabled ? L("等待 HDMI 连接空闲") : L("电视遥控器控制已关闭")
            return
        }
        let token = generation
        status = L("等待电视遥控器按键…")
        task = Task.detached(priority: .utility) { [weak self] in
            do {
                let io = try NativeCEC(connectionID: desired)
                var decoder = TVRemoteDecoder()
                while !Task.isCancelled {
                    if let sample = try TVRemoteSnapshot.read(io),
                       let action = decoder.consume(frame: sample.frame, localAddress: sample.address,
                                                    time: ProcessInfo.processInfo.systemUptime) {
                        await self?.receive(action, token: token)
                    }
                    try await Task.sleep(nanoseconds: 20_000_000)
                }
            } catch is CancellationError {
            } catch {
                await self?.failed(error.localizedDescription, token: token)
            }
        }
    }
    private func failed(_ message: String, token: UUID) {
        guard token == generation else { return }
        status = message; task = nil
    }
    private func receive(_ received: TVRemoteAction, token: UUID) {
        guard enabled, token == generation else { return }
        let titles: [TVRemoteAction: String] = [.play: L("播放"), .pause: L("暂停"), .stop: L("停止"),
            .togglePlayPause: L("确认"), .next: L("下一首"), .previous: L("上一首"),
            .volumeUp: L("音量加"), .volumeDown: L("音量减"), .mute: L("静音"),
            .up: L("向上"), .down: L("向下"), .left: L("向左"), .right: L("向右")]
        lastReceived = L("收到电视按键：%@", titles[received] ?? received.rawValue)
        guard let action = received.mediaAction(navigationEnabled: mapNavigation) else {
            status = L("方向键保留原有操作"); return
        }
        if action == .togglePlayPause && !mapSelect {
            status = L("确认键保留原有操作"); return
        }
        switch action {
        case .volumeUp, .volumeDown, .mute:
            status = Self.adjustVolume(action) ? L("已调整 Mac 输出音量") : L("当前输出不支持 Mac 软件音量，请用电视自身音量控制")
        default:
            let commands: [TVRemoteAction: UInt32] = [.play: 0, .pause: 1, .togglePlayPause: 2, .stop: 3, .next: 4, .previous: 5]
            guard let command = commands[action], let send = Self.sendCommand else {
                status = L("当前 macOS 不支持播放控制接口"); return
            }
            status = send(command, nil) ? L("已请求控制 Mac 播放；实际响应取决于播放器") : L("播放器未接受控制请求")
        }
    }
    // Use discrete play/pause commands, not a toggle for every incoming key.
    // No synthetic volume key events: those would loop through SystemVolumeBridge back to the TV.
    private typealias SendCommand = @convention(c) (UInt32, CFDictionary?) -> Bool
    private static let mediaRemote = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY)
    private static let sendCommand: SendCommand? = {
        guard let library = mediaRemote, let function = dlsym(library, "MRMediaRemoteSendCommand") else { return nil }
        return unsafeBitCast(function, to: SendCommand.self)
    }()

    private static func adjustVolume(_ action: TVRemoteAction) -> Bool {
        var property = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0), size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, &size, &device) == noErr else { return false }
        property = AudioObjectPropertyAddress(mSelector: action == .mute ? kAudioDevicePropertyMute : kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var writable = DarwinBoolean(false)
        guard AudioObjectIsPropertySettable(device, &property, &writable) == noErr, writable.boolValue else { return false }
        if action == .mute {
            var value: UInt32 = 0; size = 4
            guard AudioObjectGetPropertyData(device, &property, 0, nil, &size, &value) == noErr else { return false }
            value = value == 0 ? 1 : 0
            return AudioObjectSetPropertyData(device, &property, 0, nil, 4, &value) == noErr
        }
        var value: Float32 = 0; size = 4
        guard AudioObjectGetPropertyData(device, &property, 0, nil, &size, &value) == noErr else { return false }
        value = min(1, max(0, value + (action == .volumeUp ? 1 : -1) / 16))
        return AudioObjectSetPropertyData(device, &property, 0, nil, 4, &value) == noErr
    }
}
