import Foundation
import SwiftUI

/// Supported in-app languages and the shared storage key used by Settings and localization helpers.
enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case german = "de"

    static let storageKey = "mappy.languageCode"

    var id: String {
        rawValue
    }

    var locale: Locale {
        Locale(identifier: rawValue)
    }

    var localizedName: LocalizedStringKey {
        switch self {
        case .english:
            return "English"
        case .german:
            return "German"
        }
    }

    static var selected: AppLanguage {
        let storedCode = UserDefaults.standard.string(forKey: storageKey)
        return AppLanguage(rawValue: storedCode ?? "") ?? .english
    }
}

enum MappyLocalization {
    static func string(_ key: String.LocalizationValue) -> String {
        String(localized: key, locale: AppLanguage.selected.locale)
    }
}
