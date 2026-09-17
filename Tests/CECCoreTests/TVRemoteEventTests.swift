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

extension TVRemoteEventTests {
    func testNavigationMappingIsOptInAndPreservesDedicatedMediaKeys() {
        let keys: [(UInt8, TVRemoteAction, TVRemoteAction)] = [
            (1, .up, .previousApp), (2, .down, .nextApp),
            (3, .left, .previous), (4, .right, .next)
        ]
        var decoder = TVRemoteDecoder()
        _ = decoder.consume(frame: [4], localAddress: 4, time: 0)
        for (key, direction, mapped) in keys {
            _ = decoder.consume(frame: [4, 0x45], localAddress: 4, time: 1)
            let result = decoder.consume(frame: [4, 0x44, key], localAddress: 4, time: 2)
            XCTAssertEqual(result, direction)
            XCTAssertNil(result?.mediaAction(navigationEnabled: false))
            XCTAssertEqual(result?.mediaAction(navigationEnabled: true), mapped)
            XCTAssertNil(decoder.consume(frame: [4, 0x44, key], localAddress: 4, time: 3))
        }
        XCTAssertEqual(TVRemoteAction.next.mediaAction(navigationEnabled: false), .next)
        XCTAssertEqual(TVRemoteAction.previous.mediaAction(navigationEnabled: false), .previous)
    }
}

extension TVRemoteEventTests {
    func testMouseDirectionsDoNotConvertMediaKeysIntoPointerMovement() {
        XCTAssertEqual(TVRemoteAction.left.pointerOffset?.x, -24)
        XCTAssertEqual(TVRemoteAction.right.pointerOffset?.x, 24)
        XCTAssertEqual(TVRemoteAction.up.pointerOffset?.y, -24)
        XCTAssertEqual(TVRemoteAction.down.pointerOffset?.y, 24)
        for action: TVRemoteAction in [.play, .pause, .next, .previous, .volumeUp, .mute, .togglePlayPause] {
            XCTAssertNil(action.pointerOffset)
        }
        XCTAssertEqual(TVRemoteMode(rawValue: "mouse"), .mouse)
        XCTAssertNil(TVRemoteMode(rawValue: "unknown"))
    }
}

extension TVRemoteEventTests {
    func testHoldAccelerationReleaseAndWatchdog() throws {
        var motion = TVPointerMotion()
        motion.press(.right, time: 0)
        XCTAssertNil(motion.step(time: 0.1))
        let slow = try XCTUnwrap(motion.step(time: 0.18))
        var fast = slow
        for tick in 10...70 { fast = try XCTUnwrap(motion.step(time: Double(tick) * 0.02)) }
        XCTAssertGreaterThan(fast.distance / 0.02, slow.distance / 0.08)
        motion.stop()
        XCTAssertNil(motion.step(time: 1.42))
        motion.press(.left, time: 2)
        XCTAssertNil(motion.step(time: 2.3)) // stalled run loop: no jump
        motion.press(.down, time: 3)
        for tick in 1...199 { _ = motion.step(time: 3 + Double(tick) * 0.02) }
        XCTAssertNil(motion.step(time: 7)) // lost release: bounded motion
        XCTAssertNil(motion.step(time: 7.02))
    }
    func testReleaseIsObservableWithoutTreatingStaleReadsAsRepeats() {
        var decoder = TVRemoteDecoder()
        XCTAssertNil(decoder.consumeInput(frame: [4, 0x44, 4], localAddress: 4, time: 0))
        XCTAssertEqual(decoder.consumeInput(frame: [4, 0x45], localAddress: 4, time: 1), .release)
        XCTAssertEqual(decoder.consumeInput(frame: [4, 0x44, 4], localAddress: 4, time: 2), .press(.right))
        XCTAssertNil(decoder.consumeInput(frame: [4, 0x44, 4], localAddress: 4, time: 3))
        XCTAssertNil(decoder.consumeInput(frame: [8, 0x45], localAddress: 4, time: 3.1))
        XCTAssertEqual(decoder.consumeInput(frame: [4, 0x45], localAddress: 4, time: 3.2), .release)
    }
}

extension TVRemoteEventTests {
    func testSixPointerSpeedsClampAndPreservePreviousDefault() {
        XCTAssertEqual(TVPointerSpeed(level: 3).multiplier, 1)
        XCTAssertEqual(TVPointerSpeed(level: 3).tapDistance, 6)
        XCTAssertEqual(TVPointerSpeed(level: -1).level, 1)
        XCTAssertEqual(TVPointerSpeed(level: 99).level, 6)
        for level in 2...6 {
            XCTAssertGreaterThan(TVPointerSpeed(level: level).multiplier, TVPointerSpeed(level: level - 1).multiplier)
            XCTAssertGreaterThan(TVPointerSpeed(level: level).tapDistance, TVPointerSpeed(level: level - 1).tapDistance)
        }
    }
}

extension TVRemoteEventTests {
    func testConfirmationOnlyClicksOnReleaseAndNeverClicksTwice() {
        var confirm = TVPointerConfirmation()
        XCTAssertNil(confirm.release(time: 0))
        confirm.press(time: 1)
        XCTAssertEqual(confirm.release(time: 1.2), .left)
        XCTAssertNil(confirm.release(time: 1.3))
        confirm.press(time: 2)
        confirm.press(time: 2.5) // repeat does not restart the hold
        XCTAssertEqual(confirm.release(time: 2.8), .right)
        XCTAssertNil(confirm.release(time: 2.9))
        confirm.press(time: 3)
        confirm.cancel()
        XCTAssertNil(confirm.release(time: 3.1))
        confirm.press(time: 4)
        XCTAssertNil(confirm.release(time: 8)) // stale release must not click
    }
    func testBackDecodeOnlyFromTVToThisMac() {
        var decoder = TVRemoteDecoder()
        _ = decoder.consumeInput(frame: [4], localAddress: 4, time: 0)
        XCTAssertNil(decoder.consumeInput(frame: [8, 0x44, 0x0d], localAddress: 4, time: 1))
        XCTAssertEqual(decoder.consumeInput(frame: [4, 0x44, 0x0d], localAddress: 4, time: 2), .press(.back))
    }
}
