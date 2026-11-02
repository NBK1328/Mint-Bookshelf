import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case en
    case ru

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .en: return "English"
        case .ru: return "Русский"
        }
    }

    var locale: Locale { Locale(identifier: rawValue) }

    static var preferred: AppLanguage {
        Locale.preferredLanguages.first?.hasPrefix("ru") == true ? .ru : .en
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case light
    case dark

    var id: String { rawValue }

    var colorScheme: ColorScheme {
        self == .light ? .light : .dark
    }

    var icon: String {
        self == .light ? "moon" : "sun.max"
    }
}

enum L10n {
    static func text(_ key: String, _ language: AppLanguage, _ arguments: CVarArg...) -> String {
        let format = language == .ru ? (ru[key] ?? key) : key
        return String(format: format, locale: language.locale, arguments: arguments)
    }
}

private struct AppLanguageKey: EnvironmentKey {
    static let defaultValue: AppLanguage = .en
}

extension EnvironmentValues {
    var appLanguage: AppLanguage {
        get { self[AppLanguageKey.self] }
        set { self[AppLanguageKey.self] = newValue }
    }
}
