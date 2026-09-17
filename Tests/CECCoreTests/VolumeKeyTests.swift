import XCTest
@testable import CECCore
final class VolumeKeyTests:XCTestCase {
    func testDecodesVolumeKeysAndRelease() {
        XCTAssertEqual(VolumeKey.decode(subtype:8,data:0x00000a00)?.command,"volumeUp")
        XCTAssertEqual(VolumeKey.decode(subtype:8,data:0x00010a00)?.command,"volumeDown")
        XCTAssertEqual(VolumeKey.decode(subtype:8,data:0x00070a00)?.command,"mute")
        XCTAssertEqual(VolumeKey.decode(subtype:8,data:0x00010b00)?.down,false)
        XCTAssertEqual(VolumeKey.decode(subtype:8,data:0x00010a01)?.repeating,true)
    }
    func testDoesNotCapturePlaybackBrightnessOrOtherEvents() {
        for code in [2,3,16,17,18] { XCTAssertNil(VolumeKey.decode(subtype:8,data:(code << 16) | 0x0a00)) }
        XCTAssertNil(VolumeKey.decode(subtype:0,data:0x00010a00))
        XCTAssertNil(VolumeKey.decode(subtype:8,data:0x00010000))
    }
}
