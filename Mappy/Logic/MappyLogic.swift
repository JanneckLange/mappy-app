import Foundation

/// Pure naming helpers shared by OCR analysis, UI defaults, and local assertions.
enum MappyLogic {
    /// Removes OCR noise, short fragments, and duplicates while preserving the most useful labels.
    static func cleanHints(from rawText: [String]) -> [String] {
        var seen = Set<String>()
        let cleaned = rawText
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 3 }
            .filter { text in
                let key = text.lowercased()
                if seen.contains(key) {
                    return false
                }
                seen.insert(key)
                return true
            }

        return Array(cleaned.prefix(8))
    }

    /// Chooses a readable map name from OCR hints first, then falls back to filename/date text.
    static func suggestedName(fallbackName: String, hints: [String]) -> String {
        if let candidate = hints.first(where: { $0.rangeOfCharacter(from: .letters) != nil }) {
            return candidate.capitalized
        }
        let cleanedFallback = fallbackName
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanedFallback.isEmpty ? MappyLocalization.string( "Untitled Map") : cleanedFallback.capitalized
    }

    /// Makes a filename/date fallback for imported or captured assets.
    static func fallbackName(filename: String?, date: Date = Date()) -> String {
        if let filename, !filename.isEmpty {
            return URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        }
        return DateFormatter.mappyNameFormatter.string(from: date)
    }
}
