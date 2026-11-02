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

func joinedErrors(_ errors: [String], _ language: AppLanguage) -> String {
    errors.map { L10n.error($0, language) }.joined(separator: "; ")
}

enum L10n {
    static func text(_ key: String, _ language: AppLanguage, _ arguments: CVarArg...) -> String {
        let format = language == .ru ? (ru[key] ?? key) : key
        return String(format: format, locale: language.locale, arguments: arguments)
    }

    static func error(_ message: String, _ language: AppLanguage) -> String {
        guard language == .ru else { return message }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let exact: [String: String] = [
            "not initialized": "Приложение не инициализировано",
            "no device": "Kindle не подключён",
            "device not found": "Kindle не найден",
            "not found": "Не найдено",
            "no calibre": "Calibre не найден",
            "ebook-convert not found": "Calibre не найден",
            "calibre not available": "Calibre недоступен",
            "transfer cancelled": "Передача отменена",
            "empty scan root": "Пустой путь сканирования",
            "refusing to scan the filesystem root": "Нельзя сканировать корень файловой системы",
            "entry not found": "Запись не найдена",
            "create folder failed": "Не удалось создать папку",
            "empty response": "Пустой ответ ядра",
            "request failed": "Запрос не выполнен",
            "missing response data": "В ответе нет данных",
            "task function is nil": "Внутренняя ошибка операции",
            "manager is closed": "Очередь операций закрыта",
            "queue is full": "Очередь операций переполнена",
            "open failed": "Не удалось открыть устройство",
            "The file name is not valid": "Недопустимое имя файла",
            "The destination escapes the selected folder": "Путь выходит за пределы выбранной папки",
            "The destination is not a directory": "Назначение не является папкой",
            "unnamed": "без названия",
        ]
        if let translated = exact[trimmed] {
            return translated
        }
        let prefixes: [(String, String)] = [
            ("detect failed", "Ошибка поиска устройства"),
            ("upload failed", "Ошибка загрузки"),
            ("delete failed", "Ошибка удаления"),
            ("download failed", "Ошибка скачивания"),
            ("move failed", "Ошибка перемещения"),
            ("copy failed", "Ошибка копирования"),
            ("rename failed", "Ошибка переименования"),
            ("stdout pipe", "Ошибка Calibre"),
            ("stderr pipe", "Ошибка Calibre"),
            ("panic:", "Внутренняя ошибка"),
        ]
        let lower = trimmed.lowercased()
        for (prefix, translated) in prefixes where lower.hasPrefix(prefix) {
            return translated + trimmed.dropFirst(prefix.count)
        }
        var translated = message
        for (english, russian) in exact.sorted(by: { $0.key.count > $1.key.count }) {
            translated = translated.replacingOccurrences(of: english, with: russian)
        }
        for (english, russian) in prefixes {
            translated = translated.replacingOccurrences(of: english, with: russian)
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
