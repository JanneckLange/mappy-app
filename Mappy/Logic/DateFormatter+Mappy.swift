import Foundation

extension DateFormatter {
    /// Shared formatter for default names like "Map Jun 25, 2026".
    static let mappyNameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = .current
        return formatter
    }()
}
