import XCTest
@testable import CECCore
final class CommandRunnerTests: XCTestCase {
    func testSuccessfulCommandCapturesOutput() {
        let r = CommandRunner.run("/bin/echo", arguments: ["CEC ready"])
        XCTAssertTrue(r.succeeded)
        XCTAssertEqual(r.output.trimmingCharacters(in: .whitespacesAndNewlines), "CEC ready")
    }
    func testFailurePreservesDiagnostic() {
        let r = CommandRunner.run("/bin/sh", arguments: ["-c", "echo 'Display unavailable' >&2; exit 7"])
        XCTAssertFalse(r.succeeded)
        XCTAssertTrue(r.output.contains("Display unavailable"))
    }
    func testHungBackendIsTerminated() {
        let start = Date()
        let r = CommandRunner.run("/bin/sleep", arguments: ["10"], timeout: 0.15)
        XCTAssertTrue(r.timedOut)
        XCTAssertFalse(r.succeeded)
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }
    func testMissingExecutableIsReported() {
        let r = CommandRunner.run("/does-not-exist", arguments: [])
        XCTAssertFalse(r.succeeded)
        XCTAssertFalse(r.output.isEmpty)
    }
}
