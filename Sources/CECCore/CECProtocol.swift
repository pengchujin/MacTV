import Foundation

public protocol CECRegisters {
    func read(_ address: UInt32, count: Int) throws -> [UInt8]
    func write(_ address: UInt32, bytes: [UInt8]) throws
}
public enum CECError: Error, LocalizedError {
    case failure(String)
    public var errorDescription: String? { if case let .failure(message) = self { return message }; return nil }
}

// DP CEC register definitions are documented in VESA's AUX CEC tunnel and
// Linux include/drm/display/drm_dp.h. All writes are restricted to that block.
public final class CECSession {
    let io: CECRegisters
    let pause: (TimeInterval) -> Void
    var source: UInt8 = 4
    public private(set) var acknowledged = true
    public init(io: CECRegisters, pause: @escaping (TimeInterval) -> Void = Thread.sleep(forTimeInterval:)) { self.io = io; self.pause = pause }
    private func byte(_ address: UInt32) throws -> UInt8 { try io.read(address,count:1)[0] }
    private func scoped<T>(_ body: () throws -> T) throws -> T {
        guard try byte(0x3000) & 1 != 0 else { throw CECError.failure(L("连接不支持 HDMI-CEC")) }
        let control = try byte(0x3001)
        guard control & 1 != 0 else { throw CECError.failure(L("请在显示器设置中开启 HDMI-CEC")) }
        let original = try io.read(0x300e,count:2)
        let mask = UInt16(original[0]) | UInt16(original[1]) << 8
        // Reuse macOS's playback address; never impersonate the TV/audio receiver.
        guard let address = [4,8,11].first(where: { mask & (1 << $0) != 0 }) else {
            throw CECError.failure(L("Mac 尚未分配 CEC 播放设备地址，请重新连接 HDMI"))
        }
        source = UInt8(address)
        return try body()
    }
    private func transmit(_ payload: [UInt8], destination: UInt8 = 0) throws {
        guard destination < 16, payload.count <= 15 else { throw CECError.failure(L("无效的 CEC 帧")) }
        var ready = false
        for _ in 0..<100 {
            if try byte(0x3003) & 0x80 == 0 { ready = true; break }
            pause(0.01)
        }
        guard ready else { throw CECError.failure(L("CEC 通道正忙，请重试")) }
        try io.write(0x3004,bytes:[0xf0])
        let frame = [source << 4 | destination] + payload
        try io.write(0x3020,bytes:frame)
        try io.write(0x3003,bytes:[UInt8(frame.count-1) | 0x90]) // one retry
        for _ in 0..<1500 {
            let flags = try byte(0x3004)
            if flags & 0xe0 != 0 {
                try io.write(0x3004,bytes:[flags & 0xf0])
                throw CECError.failure(flags & 0x20 != 0 ? L("CEC 线路发生冲突，请重试") : String(format:L("设备未确认 CEC 指令（0x%02X）"),flags))
            }
            if flags & 0x10 != 0 {
                try io.write(0x3004,bytes:[0x10])
                return
            }
            // macOS consumes the IRQ within ~1 ms. Observe our own completed
            // TX descriptor as a fallback, without claiming an ACK was observed.
            let tx = try byte(0x3003)
            if tx == UInt8(frame.count-1) | 0x10 {
                acknowledged = false
                return
            }
            pause(0.001)
        }
        throw CECError.failure(L("CEC 发送超时"))
    }
    public func press(_ key: UInt8) throws {
        guard [UInt8(0x41),0x42,0x43].contains(key) else { throw CECError.failure(L("不支持的音量操作")) }
        try scoped {
            do { try transmit([0x44,key]) }
            catch { try? transmit([0x45]); throw error }
            pause(0.06)
            try transmit([0x45])
        }
    }
    public func sendKey(_ key: UInt8, to target: UInt8) throws {
        guard target < 15 else { throw CECError.failure(L("遥控按键必须发给单个设备")) }
        guard RemoteCommand.all.contains(where: { $0.key == key }) else { throw CECError.failure(L("未知遥控按键")) }
        try scoped {
            guard target != source else { throw CECError.failure(L("这个地址属于 Mac 自身，请选择其他设备")) }
            do { try transmit([0x44,key],destination:target) }
            catch { try? transmit([0x45],destination:target); throw error }
            pause(0.06)
            try transmit([0x45],destination:target)
        }
    }
    public func command(_ payload: [UInt8], to target: UInt8) throws {
        guard target < 15, !payload.isEmpty else { throw CECError.failure(L("请选择单个设备")) }
        try scoped {
            guard target != source else { throw CECError.failure(L("不能向 Mac 自身发送遥控指令")) }
            try transmit(payload,destination:target)
        }
    }
    public func query(_ payload: [UInt8], to target: UInt8, reply: UInt8, attempts: Int = 1000) throws -> [UInt8] {
        try scoped {
            guard target < 15, target != source else { throw CECError.failure(L("请选择其他设备")) }
            let previous = try io.read(0x3010,count:16)
            if previous[1] == reply,previous[0] >> 4 == target {
                _ = try? query([reply == 0x90 ? 0x46 : 0x8f],to:target,reply:reply == 0x90 ? 0x47 : 0x90,attempts:300)
            }
            let baseline = try io.read(0x3010,count:16)
            try io.write(0x3004,bytes:[3])
            try transmit(payload,destination:target)
            for _ in 0..<attempts {
                let flags = try byte(0x3004)
                let info = try byte(0x3002)
                let frame = try io.read(0x3010,count:16)
                let fromTarget = frame[0] >> 4 == target
                let destination = frame[0] & 15
                let fresh = frame != baseline || (flags & 1 != 0 && info & 0x80 != 0 && info & 15 > 0)
                if fresh, fromTarget, destination == source || destination == 15 {
                    if frame[1] == 0, frame[2] == payload[0] {
                        throw CECError.failure(L("设备拒绝此功能（Feature Abort，原因 %@）", String(frame[3])))
                    }
                    if frame[1] == reply {
                        // Fixed-length replies don't depend on RX info, which macOS may consume.
                        let lengths: [UInt8:Int] = [0x90:3,0x7a:3,0x7e:3,0x9e:3,0x84:5,0x87:5,0x1b:3,0x8e:3]
                        if let length = lengths[reply] { return Array(frame.prefix(length)) }
                        if reply == 0x47 { return Array(frame.prefix(2)) + Array(frame.dropFirst(2).prefix { $0 >= 32 && $0 < 127 }) }
                        if info & 15 > 1 { return Array(frame.prefix(Int(info & 15)+1)) }
                        // Variable-length feature replies need a trustworthy length.
                    }
                }
                pause(0.001)
            }
            throw CECError.failure(L("未收到新的状态回复；设备可能不支持此查询，或回复被系统接收"))
        }
    }
    public func activateMac(physical address:UInt16) throws {
        guard EDIDAddress.valid(address) else { throw CECError.failure(L("无效的 HDMI 物理地址")) }
        try scoped {
            try transmit([0x04],destination:0)
            try transmit([0x82,UInt8(address >> 8),UInt8(address & 255)],destination:15)
        }
    }
    public func route(to address: UInt16) throws {
        guard EDIDAddress.valid(address) else { throw CECError.failure(L("无效的 HDMI 输入地址")) }
        try scoped {
            try transmit([0x86, UInt8(address >> 8), UInt8(address & 255)], destination: 15)
        }
    }
    public func discover() throws -> [CECDevice] {
        var devices: [CECDevice] = []
        try scoped {
            for address in [UInt8(0),5,4,8,11,1,2,9,3,6,7,10,12,13,14] where address != source {
                if let _ = try? query([0x8f],to:address,reply:0x90,attempts:300) {
                    var name = CECDevice.role(address)
                    if let frame = try? query([0x46],to:address,reply:0x47,attempts:350), let value = String(bytes:frame.dropFirst(2),encoding:.ascii), !value.isEmpty { name=value }
                    devices.append(CECDevice(address:address,name:name))
                }
            }
        }
        return devices
    }
    public func probe() throws -> String {
        try scoped {
            let baseline = try io.read(0x3010,count:16)
            // Alternate response types so a previous response cannot pass as fresh.
            // macOS can overwrite RX_MESSAGE_INFO with a poll before we read it,
            // while the last complete payload is still in RX_MESSAGE_BUFFER.
            let wantName = baseline[1] == 0x90
            let expected: UInt8 = wantName ? 0x47 : 0x90
            try io.write(0x3004,bytes:[0x03])
            try transmit([wantName ? 0x46 : 0x8f])
            for _ in 0..<2500 {
                let frame = try io.read(0x3010,count:16)
                if frame != baseline, frame[0] == source, frame[1] == expected {
                    if wantName {
                        let name = frame.dropFirst(2).prefix { $0 >= 0x20 && $0 < 0x7f }
                        return String(bytes:name,encoding:.ascii) ?? L("HDMI 显示器")
                    }
                    guard frame[2] <= 3 else { throw CECError.failure(L("显示器返回了无效的电源状态")) }
                    return L("HDMI 显示器")
                }
                pause(0.001)
            }
            throw CECError.failure(L("显示器未回应，请重试连接"))
        }
    }
}
