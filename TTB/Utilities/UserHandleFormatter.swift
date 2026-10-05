import Foundation

enum UserHandleFormatter {
    static func handle(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "@ttb-user" }
        return trimmed.hasPrefix("@") ? trimmed : "@\(trimmed)"
    }
}
