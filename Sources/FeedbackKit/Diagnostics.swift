#if os(iOS) || os(macOS)
import Foundation
#if os(iOS)
import UIKit
#endif

struct Diagnostics: Equatable {
    var appVersion: String
    var system: String
    var device: String
    var language: String

    @MainActor
    static var current: Diagnostics {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = info["CFBundleVersion"] as? String ?? "Unknown"
        #if os(iOS)
            let system = "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
            let device = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? self.sysctl("hw.machine")
        #else
            let os = ProcessInfo.processInfo.operatingSystemVersion
            let system = "macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
            let device = self.sysctl("hw.model")
        #endif
        return Diagnostics(
            appVersion: "\(version) (\(build))",
            system: system,
            device: device ?? "Unknown",
            language: Locale.current.language.languageCode?.identifier ?? "Unknown")
    }

    private static func sysctl(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var value = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return String(decoding: value.prefix { $0 != 0 }, as: UTF8.self)
    }
}
#endif
