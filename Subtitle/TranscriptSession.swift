import Foundation

struct TranscriptSession: Identifiable, Codable, Equatable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date
    let language: SupportedLanguage
    let rawText: String
    let correctedText: String?
    let llmEnabled: Bool
    let llmModel: String?
    let translatedText: String?
    let translationLanguage: SupportedLanguage?

    var displayText: String {
        if let correctedText, correctedText.isEmpty == false {
            return correctedText
        }
        return rawText
    }
}
