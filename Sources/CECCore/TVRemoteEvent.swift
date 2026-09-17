import Foundation

public enum TVRemoteMode: String, CaseIterable, Sendable {
    case media, mouse
}

public enum TVRemoteAction: String, Sendable {
    case play, pause, stop, togglePlayPause, next, previous, volumeUp, volumeDown, mute
    case up, down, left, right, back, previousApp, nextApp

    public var pointerOffset: (x: Double, y: Double)? {
        switch self {
        case .up: return (0, -24)
        case .down: return (0, 24)
        case .left: return (-24, 0)
        case .right: return (24, 0)
        default: return nil
        }
    }

    public func mediaAction(navigationEnabled: Bool) -> TVRemoteAction? {
        switch self {
        case .up: return navigationEnabled ? .previousApp : nil
        case .down: return navigationEnabled ? .nextApp : nil
        case .left: return navigationEnabled ? .previous : nil
        case .right: return navigationEnabled ? .next : nil
        default: return self
        }
    }
}

public enum TVRemoteInput: Equatable, Sendable {
    case press(TVRemoteAction)
    case release
}

/// A bounded hold: repeated reads of the same hardware buffer never renew it.
public struct TVPointerSpeed {
    public let level: Int
    public init(level: Int) { self.level = min(6, max(1, level)) }
    public var multiplier: Double { [0.35, 0.6, 1.0, 1.4, 1.9, 2.5][level - 1] }
    public var tapDistance: Double { [2.0, 4.0, 6.0, 8.0, 10.0, 12.0][level - 1] }
}

public enum TVPointerClick: Equatable { case left, right }

/// A short click is delayed until release so holding OK cannot also left-click.
public struct TVPointerConfirmation {
    private var started: TimeInterval?
    public init() {}
    public mutating func press(time: TimeInterval) {
        if started == nil { started = time }
    }
    public mutating func cancel() { started = nil }
    public mutating func release(time: TimeInterval) -> TVPointerClick? {
        defer { started = nil }
        guard let started, time >= started, time - started < 4 else { return nil }
        return time - started >= 0.65 ? .right : .left
    }
}

public struct TVPointerMotion {
    private var direction: TVRemoteAction?
    private var started: TimeInterval = 0
    private var lastStep: TimeInterval = 0
    public init() {}
    public mutating func press(_ action: TVRemoteAction, time: TimeInterval) {
        guard action.pointerOffset != nil else { stop(); return }
        direction = action; started = time; lastStep = time
    }
    public mutating func stop() { direction = nil }
    public mutating func step(time: TimeInterval) -> (direction: TVRemoteAction, distance: Double)? {
        guard let direction else { return nil }
        let age = time - started
        // A lost release must not leave the cursor moving indefinitely.
        guard age >= 0, age < 4, time - lastStep < 0.2 else { stop(); return nil }
        let dt = max(0, time - lastStep)
        lastStep = time
        guard age >= 0.16 else { return nil }
        let progress = min(1, (age - 0.16) / 1.2)
        let speed = 90 + 810 * progress * progress * (3 - 2 * progress)
        return (direction, speed * dt)
    }
}

/// Passive observer: never clears macOS-owned IRQs or changes logical addresses.
public struct TVRemoteDecoder {
    private var previous: [UInt8]?
    private var held: UInt8?
    private var lastPress: TimeInterval = 0
    public init() {}

    public mutating func consume(frame: [UInt8], localAddress: UInt8, time: TimeInterval) -> TVRemoteAction? {
        guard case let .press(action) = consumeInput(frame: frame, localAddress: localAddress, time: time) else { return nil }
        return action
    }

    public mutating func consumeInput(frame: [UInt8], localAddress: UInt8, time: TimeInterval) -> TVRemoteInput? {
        defer { previous = frame }
        // Discard the initial buffer, which may contain a key from before enabling.
        guard let previous, frame != previous else { return nil }
        guard [4, 8, 11].contains(localAddress), frame.count >= 2,
              frame[0] == localAddress else { return nil } // TV (0) -> this Mac only
        if frame[1] == 0x45, frame.count == 2 { held = nil; return .release }
        guard frame[1] == 0x44, frame.count == 3 else { return nil }
        let key = frame[2]
        let repeatPress = held == key && time - lastPress < 0.6
        held = key; lastPress = time
        guard !repeatPress else { return nil }
        switch key {
        case 0x00: return .press(.togglePlayPause)
        case 0x01: return .press(.up)
        case 0x02: return .press(.down)
        case 0x03: return .press(.left)
        case 0x04: return .press(.right)
        case 0x0d: return .press(.back)
        case 0x41: return .press(.volumeUp)
        case 0x42: return .press(.volumeDown)
        case 0x43: return .press(.mute)
        case 0x44: return .press(.play)
        case 0x45: return .press(.stop)
        case 0x46: return .press(.pause)
        case 0x4b: return .press(.next)
        case 0x4c: return .press(.previous)
        default: return nil
        }
    }
}

public enum TVRemoteSnapshot {
    public static func read(_ io: CECRegisters) throws -> (address: UInt8, frame: [UInt8])? {
        let mask = try io.read(0x300e, count: 2)
        let bits = UInt16(mask[0]) | UInt16(mask[1]) << 8
        let addresses = [UInt8(4), 8, 11].filter { bits & (1 << $0) != 0 }
        guard addresses.count == 1 else { return nil }
        let before = try io.read(0x3002, count: 1)[0]
        guard before & 0x80 != 0 else { return nil }
        let length = Int(before & 15) + 1
        let frame = try io.read(0x3010, count: length)
        let after = try io.read(0x3002, count: 1)[0]
        // Reject a buffer that changed while reading. Never infer length from stale tail bytes.
        guard before == after, frame == (try io.read(0x3010, count: length)) else { return nil }
        return (addresses[0], frame)
    }
}
