import Foundation

/// The six official languages of the United Nations. Source strings are Simplified Chinese
/// and double as lookup keys; translations live in `Resources/Localization/<code>.lproj`.
public enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case chinese = "zh-Hans", english = "en", french = "fr", spanish = "es", russian = "ru", arabic = "ar"

    public static let preferenceKey = "appLanguage"
    public var id: String { rawValue }
    public var nativeName: String {
        switch self {
        case .chinese: return "简体中文"
        case .english: return "English"
        case .french: return "Français"
        case .spanish: return "Español"
        case .russian: return "Русский"
        case .arabic: return "العربية"
        }
    }
    public var isRightToLeft: Bool { self == .arabic }
    public var locale: Locale { Locale(identifier: rawValue) }
    /// On-device recognizer locale used for spoken answers.
    public var speechLocaleIdentifier: String {
        switch self {
        case .chinese: return "zh-CN"
        case .english: return "en-US"
        case .french: return "fr-FR"
        case .spanish: return "es-ES"
        case .russian: return "ru-RU"
        case .arabic: return "ar-SA"
        }
    }

    /// First supported language in the user's preference list; English otherwise.
    public static func resolve(_ preferred: [String]) -> AppLanguage {
        for identifier in preferred {
            let lower = identifier.lowercased().replacingOccurrences(of: "_", with: "-")
            if lower.hasPrefix("zh") { return .chinese }
            let code = lower.split(separator: "-").first.map(String.init) ?? lower
            if let match = allCases.first(where: { $0.rawValue == code }) { return match }
        }
        return .english
    }

    /// Explicit in-app choice, otherwise the system preference.
    public static var current: AppLanguage {
        if let stored = UserDefaults.standard.string(forKey: preferenceKey), let language = AppLanguage(rawValue: stored) {
            return language
        }
        return resolve(Locale.preferredLanguages)
    }
}

public enum Localizer {
    private static let lock = NSLock()
    private static var bundles: [AppLanguage: Bundle] = [:]

    public static func bundle(for language: AppLanguage) -> Bundle? {
        lock.lock(); defer { lock.unlock() }
        if let cached = bundles[language] { return cached }
        guard let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return nil }
        bundles[language] = bundle
        return bundle
    }

    public static func string(_ key: String, language: AppLanguage = .current) -> String {
        bundle(for: language)?.localizedString(forKey: key, value: key, table: nil) ?? key
    }
}

/// Localized, formatted user-facing text. Missing translations fall back to the Chinese key.
public func L(_ key: String, _ arguments: CVarArg...) -> String {
    let language = AppLanguage.current
    let format = Localizer.string(key, language: language)
    return arguments.isEmpty ? format : String(format: format, locale: language.locale, arguments: arguments)
}

public enum NumberInput {
    /// Accepts decimal commas and Arabic-Indic, Persian or full-width digits typed on localized keyboards.
    public static func parse(_ text: String) -> Double? {
        var normalized = ""
        for scalar in text.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars {
            switch scalar.value {
            case 0x0660...0x0669: normalized.unicodeScalars.append(Unicode.Scalar(scalar.value - 0x0660 + 0x30)!)
            case 0x06F0...0x06F9: normalized.unicodeScalars.append(Unicode.Scalar(scalar.value - 0x06F0 + 0x30)!)
            case 0xFF10...0xFF19: normalized.unicodeScalars.append(Unicode.Scalar(scalar.value - 0xFF10 + 0x30)!)
            case 0x002C, 0x066B, 0xFF0C, 0xFF0E: normalized.append(".")
            case 0x2212, 0xFF0D: normalized.append("-")
            default: normalized.unicodeScalars.append(scalar)
            }
        }
        guard let value = Double(normalized), value.isFinite else { return nil }
        return value
    }
}
