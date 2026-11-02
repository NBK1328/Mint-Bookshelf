import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case en
    case ru
    case es
    case pt
    case zh
    case fr

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .en: return "English"
        case .ru: return "Русский"
        case .es: return "Español"
        case .pt: return "Português"
        case .zh: return "中文"
        case .fr: return "Français"
        }
    }

    var locale: Locale {
        switch self {
        case .zh: return Locale(identifier: "zh-Hans")
        case .pt: return Locale(identifier: "pt-BR")
        default: return Locale(identifier: rawValue)
        }
    }

    static var preferred: AppLanguage {
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? ""
        for language in allCases where language != .en {
            if preferred.hasPrefix(language.rawValue) {
                return language
            }
        }
        return .en
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

func joinedErrors(_ errors: [String], _ language: AppLanguage) -> String {
    errors.map { L10n.error($0, language) }.joined(separator: "; ")
}

enum L10n {
    static let tables: [AppLanguage: [String: String]] = [
        .ru: ru,
        .es: es,
        .pt: pt,
        .zh: zh,
        .fr: fr,
    ]

    private static let errorPrefixes = [
        "detect failed",
        "upload failed",
        "delete failed",
        "download failed",
        "move failed",
        "copy failed",
        "rename failed",
        "stdout pipe",
        "stderr pipe",
        "panic:",
    ]

    static func text(_ key: String, _ language: AppLanguage, _ arguments: CVarArg...) -> String {
        text(key, language, arguments: arguments)
    }

    static func text(_ key: String, _ language: AppLanguage, arguments: [CVarArg]) -> String {
        let format = tables[language]?[key] ?? key
        return String(format: format, locale: language.locale, arguments: arguments)
    }

    static func error(_ message: String, _ language: AppLanguage) -> String {
        guard language != .en else { return message }
        let table = tables[language] ?? [:]
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if let translated = table[trimmed] {
            return translated
        }
        let lower = trimmed.lowercased()
        for prefix in errorPrefixes where lower.hasPrefix(prefix) {
            if let translated = table[prefix] {
                return translated + trimmed.dropFirst(prefix.count)
            }
        }
        var translated = message
        for key in table.keys where key.contains(" ") && key.count > 4 {
            translated = translated.replacingOccurrences(of: key, with: table[key] ?? key)
        }
        return translated
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
