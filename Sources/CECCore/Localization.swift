import Foundation

/// Shared by the menu-bar app and its embedded CEC helper.
public enum Localization {
    public static let supported = ["en", "zh-Hans", "zh-Hant"]
    public static let language: String = {
        if let inherited = ProcessInfo.processInfo.environment["SCREEN_REMOTE_LANGUAGE"], supported.contains(inherited) { return inherited }
        return Bundle.preferredLocalizations(from: supported, forPreferences: UserDefaults.standard.stringArray(forKey: "AppleLanguages") ?? Locale.preferredLanguages).first ?? "en"
    }()
    private static var resourceURL: URL? {
        #if SWIFT_PACKAGE
        return Bundle.module.resourceURL
        #else
        if let url = Bundle.main.resourceURL, FileManager.default.fileExists(atPath: url.appendingPathComponent("en.lproj").path) { return url }
        // Foundation may treat a directly launched helper as an unbundled tool.
        return Bundle.main.executableURL?.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources")
        #endif
    }
    public static func text(_ key: String, language: String = language) -> String {
        guard supported.contains(language), let root = resourceURL,
              let bundle = Bundle(url: root.appendingPathComponent(language + ".lproj")) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
    public static func format(_ template: String, arguments: [String]) -> String {
        // Split first so percent signs or %@ in a device name stay literal.
        let parts = template.components(separatedBy: "%@")
        guard parts.count == arguments.count + 1 else { return template }
        return zip(arguments, parts.dropFirst()).reduce(parts[0]) { $0 + $1.0 + $1.1 }
    }
}
public func L(_ key: String, _ arguments: String...) -> String {
    let value = Localization.text(key)
    return arguments.isEmpty ? value : Localization.format(value, arguments: arguments)
}
