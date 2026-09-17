import AppKit
import CoreAudio

@MainActor final class TVRemoteBridge: ObservableObject {
    @Published var enabled = UserDefaults.standard.bool(forKey: "tvRemoteControlsMac") {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "tvRemoteControlsMac")
            configure(connection: connection, paused: paused)
        }
    }
    @Published var mode = TVRemoteMode(rawValue: UserDefaults.standard.string(forKey: "tvRemoteMode") ?? "") ?? .media {
        didSet { pointerMotion.stop(); confirmation.cancel(); UserDefaults.standard.set(mode.rawValue, forKey: "tvRemoteMode") }
    }
    @Published var pointerSpeedLevel = TVPointerSpeed(level: UserDefaults.standard.object(forKey: "tvRemotePointerSpeed") == nil ? 3 : UserDefaults.standard.integer(forKey: "tvRemotePointerSpeed")).level {
        didSet {
            pointerMotion.stop()
            UserDefaults.standard.set(pointerSpeedLevel, forKey: "tvRemotePointerSpeed")
        }
    }
    private var pointerSpeed: TVPointerSpeed { TVPointerSpeed(level: pointerSpeedLevel) }
    @Published var status = L("电视遥控器控制已关闭")
    @Published var lastReceived = ""
    private var pointerMotion = TVPointerMotion()
    private var confirmation = TVPointerConfirmation()
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
        pointerMotion.stop(); confirmation.cancel()
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
                    let sample = try TVRemoteSnapshot.read(io)
                    let input = sample.flatMap {
                        decoder.consumeInput(frame: $0.frame, localAddress: $0.address,
                                             time: ProcessInfo.processInfo.systemUptime)
                    }
                    await self?.poll(input, valid: sample != nil, token: token)
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
        pointerMotion.stop(); confirmation.cancel()
        status = message; task = nil
    }
    private func poll(_ input: TVRemoteInput?, valid: Bool, token: UUID) {
        guard enabled, token == generation else { return }
        guard valid else { pointerMotion.stop(); confirmation.cancel(); return }
        if let input {
            switch input {
            case .release:
                pointerMotion.stop()
                if mode == .mouse, let click = confirmation.release(time: ProcessInfo.processInfo.systemUptime) {
                    performPointer(.togglePlayPause, rightClick: click == .right)
                } else { confirmation.cancel() }
            case .press(let action): receive(action, token: token)
            }
        }
        guard mode == .mouse else { pointerMotion.stop(); return }
        if let movement = pointerMotion.step(time: ProcessInfo.processInfo.systemUptime) {
            performPointer(movement.direction, distance: movement.distance * pointerSpeed.multiplier)
        }
    }

    private func receive(_ received: TVRemoteAction, token: UUID) {
        guard enabled, token == generation else { return }
        let titles: [TVRemoteAction: String] = [.play: L("播放"), .pause: L("暂停"), .stop: L("停止"),
            .togglePlayPause: L("确认"), .next: L("下一首"), .previous: L("上一首"),
            .volumeUp: L("音量加"), .volumeDown: L("音量减"), .mute: L("静音"),
            .back: L("返回"), .up: L("向上"), .down: L("向下"), .left: L("向左"), .right: L("向右")]
        lastReceived = L("收到电视按键：%@", titles[received] ?? received.rawValue)
        if received != .togglePlayPause { confirmation.cancel() }
        if received == .back {
            pointerMotion.stop()
            postKeyboard(key: 53)
            return
        }
        if mode == .mouse, received.pointerOffset != nil || received == .togglePlayPause {
            if received.pointerOffset != nil {
                pointerMotion.press(received, time: ProcessInfo.processInfo.systemUptime)
                performPointer(received, distance: pointerSpeed.tapDistance)
            } else {
                pointerMotion.stop()
                confirmation.press(time: ProcessInfo.processInfo.systemUptime)
            }
            return
        }
        pointerMotion.stop()
        guard let action = received.mediaAction(navigationEnabled: true) else { return }
        switch action {
        case .previousApp: postKeyboard(key: 48, flags: [.maskCommand, .maskShift])
        case .nextApp: postKeyboard(key: 48, flags: .maskCommand)
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
    private func performPointer(_ action: TVRemoteAction, distance: Double = 24, rightClick: Bool = false) {
        guard AXIsProcessTrusted() else {
            pointerMotion.stop(); confirmation.cancel()
            status = L("鼠标控制需要辅助功能权限，请在设置的键盘部分允许辅助功能")
            return
        }
        guard let position = CGEvent(source: nil)?.location else { return }
        if let offset = action.pointerOffset {
            // Use Quartz coordinates throughout, including displays above or left of the main display.
            var count: UInt32 = 0
            var displays = [CGDirectDisplayID](repeating: 0, count: 32)
            guard CGGetActiveDisplayList(32, &displays, &count) == .success, count > 0 else { return }
            let target = CGPoint(x: position.x + offset.x / 24 * distance, y: position.y + offset.y / 24 * distance)
            let candidates = displays.prefix(Int(count)).map { display -> CGPoint in
                let bounds = CGDisplayBounds(display)
                return CGPoint(x: min(max(target.x, bounds.minX), bounds.maxX - 1),
                               y: min(max(target.y, bounds.minY), bounds.maxY - 1))
            }
            let point = candidates.min {
                hypot($0.x - target.x, $0.y - target.y) < hypot($1.x - target.x, $1.y - target.y)
            } ?? position
            guard let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                                      mouseCursorPosition: point, mouseButton: .left) else { return }
            event.post(tap: .cghidEventTap)
            status = L("已请求移动鼠标")
        } else {
            guard let down = CGEvent(mouseEventSource: nil, mouseType: rightClick ? .rightMouseDown : .leftMouseDown,
                                     mouseCursorPosition: position, mouseButton: rightClick ? .right : .left),
                  let up = CGEvent(mouseEventSource: nil, mouseType: rightClick ? .rightMouseUp : .leftMouseUp,
                                   mouseCursorPosition: position, mouseButton: rightClick ? .right : .left) else { return }
            down.setIntegerValueField(.mouseEventClickState, value: 1)
            up.setIntegerValueField(.mouseEventClickState, value: 1)
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            status = rightClick ? L("已请求右键菜单") : L("已请求鼠标单击")
        }
    }

    private func postKeyboard(key: CGKeyCode, flags: CGEventFlags = []) {
        guard AXIsProcessTrusted() else {
            status = L("请允许辅助功能以使用遥控按键")
            return
        }
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: false) else { return }
        // Post balanced modifier events so the application switcher cannot remain open.
        let commandDown = flags.contains(.maskCommand) ? CGEvent(keyboardEventSource: nil, virtualKey: 55, keyDown: true) : nil
        let commandUp = flags.contains(.maskCommand) ? CGEvent(keyboardEventSource: nil, virtualKey: 55, keyDown: false) : nil
        let shiftDown = flags.contains(.maskShift) ? CGEvent(keyboardEventSource: nil, virtualKey: 56, keyDown: true) : nil
        let shiftUp = flags.contains(.maskShift) ? CGEvent(keyboardEventSource: nil, virtualKey: 56, keyDown: false) : nil
        commandDown?.flags = .maskCommand; commandUp?.flags = []
        shiftDown?.flags = flags; shiftUp?.flags = flags.subtracting(.maskShift)
        commandDown?.post(tap: .cghidEventTap); shiftDown?.post(tap: .cghidEventTap)
        down.flags = flags; up.flags = flags
        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
        shiftUp?.post(tap: .cghidEventTap); commandUp?.post(tap: .cghidEventTap)
        status = L("已发送快捷键")
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
