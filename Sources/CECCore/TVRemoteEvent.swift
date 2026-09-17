import Foundation

public enum TVRemoteAction: String, Sendable {
    case play, pause, stop, togglePlayPause, next, previous, volumeUp, volumeDown, mute
}

/// Passive observer: never clears macOS-owned IRQs or changes logical addresses.
public struct TVRemoteDecoder {
    private var previous: [UInt8]?
    private var held: UInt8?
    private var lastPress: TimeInterval = 0
    public init() {}

    public mutating func consume(frame: [UInt8], localAddress: UInt8, time: TimeInterval) -> TVRemoteAction? {
        defer { previous = frame }
        // Discard the initial buffer, which may contain a key from before enabling.
        guard let previous, frame != previous else { return nil }
        guard [4, 8, 11].contains(localAddress), frame.count >= 2,
              frame[0] == localAddress else { return nil } // TV (0) -> this Mac only
        if frame[1] == 0x45, frame.count == 2 { held = nil; return nil }
        guard frame[1] == 0x44, frame.count == 3 else { return nil }
        let key = frame[2]
        let repeatPress = held == key && time - lastPress < 0.6
        held = key; lastPress = time
        guard !repeatPress else { return nil }
        switch key {
        case 0x00: return .togglePlayPause
        case 0x41: return .volumeUp
        case 0x42: return .volumeDown
        case 0x43: return .mute
        case 0x44: return .play
        case 0x45: return .stop
        case 0x46: return .pause
        case 0x4b: return .next
        case 0x4c: return .previous
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
