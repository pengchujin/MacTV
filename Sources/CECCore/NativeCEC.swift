import Foundation
import IOKit
import Darwin

public final class NativeCEC: CECRegisters {
    private typealias Create = @convention(c) (CFAllocator?, io_service_t) -> UnsafeMutableRawPointer?
    private typealias Read = @convention(c) (UnsafeMutableRawPointer, UInt32, UnsafeMutableRawPointer, UInt32) -> Int32
    private typealias Write = @convention(c) (UnsafeMutableRawPointer, UInt32, UnsafeRawPointer, UInt32) -> Int32
    private let device: UnsafeMutableRawPointer
    private let readFunction: Read
    private let writeFunction: Write
    // Keep the system framework loaded for the process lifetime.
    private static let library = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY)
    public init(connectionID: UInt64? = nil) throws {
        guard let library = Self.library,
              let c = dlsym(library,"IODPDeviceCreateWithService"),
              let r = dlsym(library,"IODPDeviceReadDPCD"),
              let w = dlsym(library,"IODPDeviceWriteDPCD") else {
            throw CECError.failure(L("当前 macOS 缺少 CEC 通道接口"))
        }
        let create = unsafeBitCast(c,to:Create.self)
        readFunction = unsafeBitCast(r,to:Read.self)
        writeFunction = unsafeBitCast(w,to:Write.self)
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,IOServiceMatching("DCPDPDeviceProxy"),&iterator) == KERN_SUCCESS else {
            throw CECError.failure(L("无法查找 HDMI 设备"))
        }
        defer { IOObjectRelease(iterator) }
        var devices: [UnsafeMutableRawPointer] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var entryID: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(service,&entryID)
            if let connectionID, connectionID != entryID { continue }
            guard let candidate = create(kCFAllocatorDefault,service) else { continue }
            var cap: UInt8 = 0
            if readFunction(candidate,0x3000,&cap,1) == 0, cap & 1 != 0 {
                devices.append(candidate)
            } else { _ = Unmanaged<AnyObject>.fromOpaque(candidate).takeRetainedValue() }
        }
        guard devices.count == 1 else {
            for candidate in devices { _ = Unmanaged<AnyObject>.fromOpaque(candidate).takeRetainedValue() }
            throw CECError.failure(devices.isEmpty ? L("未找到支持 CEC 的 HDMI 连接") : L("检测到多个 CEC 连接，请先选择连接"))
        }
        device = devices[0]
    }
    public static func connections() throws -> [CECConnection] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,IOServiceMatching("DCPDPDeviceProxy"),&iterator) == KERN_SUCCESS else { throw CECError.failure(L("无法读取 HDMI 连接")) }
        defer { IOObjectRelease(iterator) }
        var found: [CECConnection] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var id: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(service,&id)
            if let _ = try? NativeCEC(connectionID:id) { found.append(CECConnection(id:id,name:L("HDMI 连接 %@", String(found.count+1)))) }
        }
        return found
    }
    public static func macPhysicalAddress(connectionID:UInt64?) throws -> UInt16 {
        // Refuse an ambiguous mapping rather than announcing another port's address.
        let buses=try connections()
        guard buses.count == 1,connectionID == nil || buses[0].id == connectionID else { throw CECError.failure(L("多连接环境尚不能可靠匹配 Mac 物理地址；请使用设备的输入源菜单")) }
        typealias CopyEDID = @convention(c) (UnsafeMutableRawPointer,UnsafeMutablePointer<Unmanaged<CFData>?>) -> Int32
        guard let library,let c=dlsym(library,"IOAVServiceCreateWithService"),let e=dlsym(library,"IOAVServiceCopyEDID") else { throw CECError.failure(L("当前系统无法读取 HDMI 地址")) }
        let create=unsafeBitCast(c,to:Create.self),copy=unsafeBitCast(e,to:CopyEDID.self)
        var iterator:io_iterator_t=0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,IOServiceMatching("DCPAVServiceProxy"),&iterator) == KERN_SUCCESS else { throw CECError.failure(L("无法读取 HDMI 地址")) }
        defer { IOObjectRelease(iterator) }
        var edids:[[UInt8]]=[]
        while case let service=IOIteratorNext(iterator),service != 0 {
            defer { IOObjectRelease(service) }
            let location=IORegistryEntryCreateCFProperty(service,"Location" as CFString,kCFAllocatorDefault,0)?.takeRetainedValue() as? String
            guard location == "External",let av=create(kCFAllocatorDefault,service) else { continue }
            defer { _=Unmanaged<AnyObject>.fromOpaque(av).takeRetainedValue() }
            var data:Unmanaged<CFData>?
            if copy(av,&data) == 0,let data { edids.append(Array(data.takeRetainedValue() as Data)) }
        }
        guard edids.count == 1,let address=EDIDAddress.physical(edids[0]) else { throw CECError.failure(L("无法可靠读取 Mac 的 HDMI 物理地址；请使用输入源菜单")) }
        return address
    }
    deinit { _ = Unmanaged<AnyObject>.fromOpaque(device).takeRetainedValue() }
    public func read(_ address: UInt32, count: Int) throws -> [UInt8] {
        guard address >= 0x3000, count > 0, count <= 16, address + UInt32(count) <= 0x3030 else { throw CECError.failure(L("无效的 CEC 读取范围")) }
        var bytes = [UInt8](repeating:0,count:count)
        let result = bytes.withUnsafeMutableBytes { readFunction(device,address,$0.baseAddress!,UInt32(count)) }
        guard result == 0 else { throw CECError.failure(String(format:L("CEC 读取失败：0x%08X"),result)) }
        return bytes
    }
    public func write(_ address: UInt32, bytes: [UInt8]) throws {
        let valid = (address == 0x3003 && bytes.count == 1) || (address == 0x3004 && bytes.count == 1) || (address == 0x300e && bytes.count == 2) || (address == 0x3020 && (1...16).contains(bytes.count))
        guard valid else { throw CECError.failure(L("无效的 CEC 写入范围")) }
        let result = bytes.withUnsafeBytes { writeFunction(device,address,$0.baseAddress!,UInt32(bytes.count)) }
        guard result == 0 else { throw CECError.failure(String(format:L("CEC 写入失败：0x%08X"),result)) }
    }
}
