import XCTest
@testable import CECCore

final class LocalizationTests: XCTestCase {
    func testMenuTranslations() {
        XCTAssertEqual(Localization.text("输入源", language: "en"), "Inputs")
        XCTAssertEqual(Localization.text("输入源", language: "zh-Hans"), "输入源")
        XCTAssertEqual(Localization.text("输入源", language: "zh-Hant"), "輸入源")
        XCTAssertEqual(Localization.text("屏幕遥控", language: "zh-Hant"), "螢幕遙控")
    }
    func testFormattingKeepsDeviceNamesLiteral() {
        XCTAssertEqual(Localization.format("Sent “%@” at %@", arguments: ["TV %@ 100%", "10:00"]), "Sent “TV %@ 100%” at 10:00")
        XCTAssertEqual(Localization.text("unrecognized-device-name", language: "en"), "unrecognized-device-name")
    }
    func testCommandIdentityDoesNotDependOnLanguage() {
        XCTAssertEqual(RemoteCommand.find("settings")?.key, 0x0a)
        XCTAssertTrue(RemoteCommand.find("volumeUp")!.isAudio)
        XCTAssertNotNil(RemoteCommand.find("route4"))
    }
}
