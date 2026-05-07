import Foundation
import AppKit

@MainActor
final class FirefoxManager: ObservableObject {
    @Published var versions: [String] = []
    @Published var profiles: [String] = []

    private static let applicationsPath = "/Applications"
    private static let profilesIniPath =
        ("~/Library/Application Support/Firefox/profiles.ini" as NSString)
            .expandingTildeInPath

    nonisolated static func isFirefoxApp(_ name: String) -> Bool {
        let lower = name.lowercased()
        return (lower.hasPrefix("firefox") || lower.hasPrefix("minefield"))
            && name.hasSuffix(".app")
    }

    nonisolated static func filterVersions(from names: [String]) -> [String] {
        names
            .filter { isFirefoxApp($0) }
            .map { String($0.dropLast(4)) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    nonisolated static func parseProfiles(from iniContent: String) -> [String] {
        var names: [String] = []
        for line in iniContent.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Name=") {
                names.append(String(trimmed.dropFirst(5)))
            }
        }
        let others = names
            .filter { $0 != "default" }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return names.contains("default") ? ["default"] + others : others
    }
}
