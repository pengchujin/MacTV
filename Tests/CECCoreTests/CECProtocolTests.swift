import XCTest
@testable import CECCore
final class Registers: CECRegisters {
    var sent: [[UInt8]] = []
    var mask: [UInt8] = [0x10, 0x80]
    var failAck = false
    var consumed = false
    var tx: UInt8 = 0
    var rx = [UInt8](repeating: 0, count: 16)
    var replyToName = false
    var replyToProbe = false
    var neverCompletes = false
    func read(_ a: UInt32, count: Int) throws -> [UInt8] {
        if a == 0x3010 { return Array(rx.prefix(count)) }
        if a == 0x3002 { return [0xd2] }
        if a == 0x3000 { return [7] }
        if a == 0x3001 { return [1] }
        if a == 0x300e { return mask }
        if a == 0x3003 { return [neverCompletes ? 0x80 : tx] }
        if a == 0x3004 { return [failAck ? 0x40 : ((neverCompletes || consumed) ? 0 : 0x10)] }
        return Array(repeating:0,count:count)
    }
    func write(_ a: UInt32, bytes: [UInt8]) throws {
        if a == 0x3020 {
            sent.append(bytes)
            if replyToName && bytes == [0x40,0x46] {
                let name=Array("MiTV-MFFU1".utf8)
                rx=[0x04,0x47]+name+Array(repeating:0,count:14-name.count)
            }
            if replyToProbe && bytes == [0x40,0x8f] { rx = [0x04,0x90,0] + Array(repeating:0,count:13) }
        }
        if a == 0x3003 { tx = bytes[0] & 0x7f }
        if a == 0x300e { mask = bytes }
    }
}
final class CECProtocolTests: XCTestCase {
    func testVolumeDownIncludesRelease() throws {
        let io = Registers()
        try CECSession(io:io,pause:{ _ in }).press(0x42)
        XCTAssertEqual(io.sent, [[0x40,0x44,0x42],[0x40,0x45]])
        XCTAssertEqual(io.mask,[0x10,0x80])
    }
    func testNegativeAcknowledgmentIsNotSuccessAndRestoresState() {
        let io = Registers(); io.failAck = true; io.mask = [0,0x81]
        XCTAssertThrowsError(try CECSession(io:io,pause:{ _ in }).press(0x42))
        XCTAssertEqual(io.mask,[0,0x81])
    }
    func testBusyTransportHasBoundedWait() {
        let io = Registers(); io.neverCompletes = true
        XCTAssertThrowsError(try CECSession(io:io,pause:{ _ in }).press(0x42))
    }
    func testSystemConsumedInterruptStillCompletesTransmission() throws {
        let io = Registers(); io.consumed = true
        try CECSession(io:io,pause:{ _ in }).press(0x42)
        XCTAssertEqual(io.sent, [[0x40,0x44,0x42],[0x40,0x45]])
    }
    func testProbeRecognizesFreshReplyAfterSystemClearsReceiveInfo() throws {
        let io = Registers(); io.replyToProbe = true
        XCTAssertEqual(try CECSession(io:io,pause:{ _ in }).probe(), "HDMI 显示器")
    }
    func testRejectsNonAudioCommands() {
        let io = Registers()
        XCTAssertThrowsError(try CECSession(io:io,pause:{ _ in }).press(0x6b))
        XCTAssertTrue(io.sent.isEmpty)
    }
}

final class RemoteRoutingTests:XCTestCase {
    func testAudioReceiverAddressAndRelease() throws {
        let io=Registers()
        try CECSession(io:io,pause:{_ in}).sendKey(0x41,to:5)
        XCTAssertEqual(io.sent,[[0x45,0x44,0x41],[0x45,0x45]])
    }
    func testBroadcastKeyCannotAffectAllDevices() {
        let io=Registers()
        XCTAssertThrowsError(try CECSession(io:io,pause:{_ in}).sendKey(0x6b,to:15))
        XCTAssertTrue(io.sent.isEmpty)
    }
    func testMacAddressCannotBeChosenAsTarget() {
        let io=Registers()
        XCTAssertThrowsError(try CECSession(io:io,pause:{_ in}).sendKey(1,to:4))
        XCTAssertTrue(io.sent.isEmpty)
    }
    func testTargetedStandbyDoesNotBroadcast() throws {
        let io=Registers()
        try CECSession(io:io,pause:{_ in}).command([0x36],to:0)
        XCTAssertEqual(io.sent,[[0x40,0x36]])
    }
    func testUnrelatedSourceReplyIsIgnored() {
        let io=Registers();io.rx=[0x54,0x90,0]+Array(repeating:0,count:13)
        XCTAssertThrowsError(try CECSession(io:io,pause:{_ in}).query([0x8f],to:0,reply:0x90,attempts:2))
    }
    func testFreshResponseDecodedWithoutRxMetadata() throws {
        let io=Registers();io.replyToProbe=true
        XCTAssertEqual(try CECSession(io:io,pause:{_ in}).query([0x8f],to:0,reply:0x90,attempts:2),[0x04,0x90,0])
    }
    func testUnknownKeyCannotReachTransport() {
        let io=Registers()
        XCTAssertThrowsError(try CECSession(io:io,pause:{_ in}).sendKey(0xff,to:0))
        XCTAssertTrue(io.sent.isEmpty)
    }
}

final class EDIDRoutingTests:XCTestCase {
    func testRejectsMalformedPhysicalPaths() {
        for address:UInt16 in [0,0xffff,0x1020,0x0100] { XCTAssertFalse(EDIDAddress.valid(address)) }
        for address:UInt16 in [0x2000,0x1230,0x1234] { XCTAssertTrue(EDIDAddress.valid(address)) }
    }
    func testCannotAnnounceMalformedMacAddress() {
        let io=Registers()
        XCTAssertThrowsError(try CECSession(io:io,pause:{_ in}).activateMac(physical:0x1020))
        XCTAssertTrue(io.sent.isEmpty)
    }
    func testActiveSourceUsesVerifiedAddressAndBroadcast() throws {
        let io=Registers()
        try CECSession(io:io,pause:{_ in}).activateMac(physical:0x2310)
        XCTAssertEqual(io.sent,[[0x40,0x04],[0x4f,0x82,0x23,0x10]])
    }
    func testEDIDRequiresValidChecksumAndHDMIVendorBlock() {
        var bytes=[UInt8](repeating:0,count:256)
        bytes.replaceSubrange(0..<8,with:[0,255,255,255,255,255,255,0]);bytes[126]=1
        bytes[128]=2;bytes[129]=3;bytes[130]=10
        bytes.replaceSubrange(132..<138,with:[0x65,3,12,0,0x20,0])
        bytes[127]=UInt8((256-bytes[0..<127].reduce(0){ ($0+Int($1)) & 255 }) & 255)
        bytes[255]=UInt8((256-bytes[128..<255].reduce(0){ ($0+Int($1)) & 255 }) & 255)
        XCTAssertEqual(EDIDAddress.physical(bytes),0x2000)
        bytes[137]=1
        XCTAssertNil(EDIDAddress.physical(bytes))
        XCTAssertNil(EDIDAddress.physical(Array(bytes.prefix(150))))
    }
    func testCachedReplyCannotMasqueradeAsFreshState() {
        let io=Registers();io.rx=[0x04,0x90,0]+Array(repeating:0,count:13)
        XCTAssertThrowsError(try CECSession(io:io,pause:{_ in}).query([0x8f],to:0,reply:0x90,attempts:2))
    }
}

final class DeviceNameTests:XCTestCase {
    func testOSDNameIsNotTruncatedByStaleReceiveLength() throws {
        let io=Registers();io.replyToName=true
        let result=try CECSession(io:io,pause:{_ in}).query([0x46],to:0,reply:0x47,attempts:2)
        XCTAssertEqual(String(bytes:result.dropFirst(2),encoding:.ascii),"MiTV-MFFU1")
    }
}

final class InputSelectionTests: XCTestCase {
    func testHDMIInputUsesSetStreamPathBroadcast() throws {
        let io = Registers()
        try CECSession(io: io, pause: { _ in }).route(to: 0x3000)
        XCTAssertEqual(io.sent, [[0x4f, 0x86, 0x30, 0]])
    }
    func testInvalidInputCannotSendAnything() {
        let io = Registers()
        XCTAssertThrowsError(try CECSession(io: io, pause: { _ in }).route(to: 0x3010))
        XCTAssertTrue(io.sent.isEmpty)
    }
    func testAllInputChoicesAreRecognized() {
        XCTAssertEqual((1...4).compactMap { RemoteCommand.find("route\($0)") }.count, 4)
    }
}


final class TelevisionMenuTests: XCTestCase {
    func testAdjustmentMenuUsesSetupKeyRatherThanHome() throws {
        let io = Registers()
        let command = RemoteCommand.adjustmentMenu
        try CECSession(io: io, pause: { _ in }).sendKey(try XCTUnwrap(command.key), to: 0)
        XCTAssertEqual(io.sent, [[0x40, 0x44, 0x0a], [0x40, 0x45]])
        XCTAssertNotEqual(command.key, RemoteCommand.find("home")?.key)
    }
}
