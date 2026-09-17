import XCTest
@testable import CECCore

final class TVRemoteEventTests: XCTestCase {
    func testStartupStaleAndRelease() {
        var d = TVRemoteDecoder()
        XCTAssertNil(d.consume(frame: [4, 0x44, 0], localAddress: 4, time: 0))
        XCTAssertNil(d.consume(frame: [4, 0x44, 0], localAddress: 4, time: 1))
        XCTAssertNil(d.consume(frame: [4, 0x45], localAddress: 4, time: 2))
        XCTAssertEqual(d.consume(frame: [4, 0x44, 0], localAddress: 4, time: 3), .togglePlayPause)
        XCTAssertNil(d.consume(frame: [4, 0x44, 0], localAddress: 4, time: 4))
    }
    func testRoutingAndMalformedFrames() {
        var d = TVRemoteDecoder()
        _ = d.consume(frame: [4], localAddress: 4, time: 0)
        for frame: [UInt8] in [[0x40, 0x44, 0x41], [0x0f, 0x44, 0x41], [0x08, 0x44, 0x41], [0x54, 0x44, 0x41], [4, 0x44], [4, 0x44, 0x44, 0]] {
            XCTAssertNil(d.consume(frame: frame, localAddress: 4, time: 1))
        }
        XCTAssertEqual(d.consume(frame: [4, 0x44, 0x46], localAddress: 4, time: 2), .pause)
    }
    func testMappingAndRepeatedPressAfterRelease() {
        var d = TVRemoteDecoder()
        _ = d.consume(frame: [8], localAddress: 8, time: 0)
        let cases: [(UInt8, TVRemoteAction)] = [(0x41,.volumeUp),(0x42,.volumeDown),(0x43,.mute),(0x44,.play),(0x45,.stop),(0x46,.pause),(0x4b,.next),(0x4c,.previous)]
        for (key, action) in cases {
            for _ in 0..<2 {
                _ = d.consume(frame: [8,0x45], localAddress: 8, time: 1)
                XCTAssertEqual(d.consume(frame: [8,0x44,key], localAddress: 8, time: 1.1),action)
            }
        }
    }
}

private final class RXRegisters: CECRegisters {
    var info: UInt8 = 0x82
    var frame: [UInt8] = [4, 0x44, 0x46]
    var changing = false
    var reads = 0
    var writes = 0
    func read(_ address: UInt32, count: Int) throws -> [UInt8] {
        switch address {
        case 0x300e: return [0x10, 0x80]
        case 0x3002: return [info]
        case 0x3010:
            reads += 1
            return changing && reads == 2 ? [4, 0x44, 0x44] : Array(frame.prefix(count))
        default: XCTFail("Unexpected register"); return []
        }
    }
    func write(_ address: UInt32, bytes: [UInt8]) throws { writes += 1 }
}

extension TVRemoteEventTests {
    func testSnapshotIsReadOnlyAndUsesReportedLength() throws {
        let io = RXRegisters()
        io.frame += [0xff, 0xff]
        let sample = try XCTUnwrap(TVRemoteSnapshot.read(io))
        XCTAssertEqual(sample.address, 4)
        XCTAssertEqual(sample.frame, [4, 0x44, 0x46])
        XCTAssertEqual(io.writes, 0)
    }
    func testTornAndIncompleteSnapshotRejected() throws {
        let io = RXRegisters()
        io.changing = true
        XCTAssertNil(try TVRemoteSnapshot.read(io))
        io.info = 2
        XCTAssertNil(try TVRemoteSnapshot.read(io))
        XCTAssertEqual(io.writes, 0)
    }
}
