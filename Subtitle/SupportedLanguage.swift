import Foundation

enum SupportedLanguage: String, CaseIterable, Codable, Identifiable {
    case english = "en-US"
    case chinese = "zh-CN"
    case japanese = "ja-JP"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english:
            return "English"
        case .chinese:
            return "简体中文"
        case .japanese:
            return "日本語"
        }
    }

    var locale: Locale {
        Locale(identifier: rawValue)
    }

    static func defaultTranslationTarget(excluding source: SupportedLanguage) -> SupportedLanguage {
        allCases.first { $0 != source } ?? .english
    }
}
