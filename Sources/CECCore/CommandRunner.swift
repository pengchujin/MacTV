import Foundation
import Darwin

public struct CommandResult: Sendable {
    public let succeeded: Bool
    public let timedOut: Bool
    public let output: String
}

public enum CommandRunner {
    public static func run(_ path: String, arguments: [String], timeout: TimeInterval = 8) -> CommandResult {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        guard FileManager.default.createFile(atPath: url.path, contents: nil),
              let file = try? FileHandle(forWritingTo: url) else {
            return CommandResult(succeeded: false, timedOut: false, output: L("无法创建诊断日志"))
        }
        defer { try? file.close(); try? FileManager.default.removeItem(at: url) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["SCREEN_REMOTE_LANGUAGE"] = Localization.language
        process.environment = environment
        process.standardOutput = file
        process.standardError = file
        let completed = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in completed.signal() }
        do { try process.run() } catch {
            return CommandResult(succeeded: false, timedOut: false, output: error.localizedDescription)
        }
        let timedOut = completed.wait(timeout: .now() + timeout) == .timedOut
        if timedOut {
            if process.isRunning { process.terminate() }
            if completed.wait(timeout: .now() + 0.3) == .timedOut, process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                process.waitUntilExit()
            }
        }
        let output = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        return CommandResult(succeeded: !timedOut && process.terminationStatus == 0, timedOut: timedOut, output: output)
    }
}
