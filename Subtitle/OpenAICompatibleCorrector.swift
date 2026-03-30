import Foundation

struct OpenAICompatibleConfiguration {
    let baseURL: URL
    let apiKey: String
    let model: String
}

enum OpenAICompatibleCorrectorError: LocalizedError {
    case invalidBaseURL
    case missingConfiguration
    case invalidResponse
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "The configured API Base URL is invalid."
        case .missingConfiguration:
            return "API Base URL, API Key, and Model are all required when LLM correction or translation is enabled."
        case .invalidResponse:
            return "The OpenAI-compatible API returned an invalid response."
        case .emptyResponse:
            return "The OpenAI-compatible API returned an empty transcript."
        }
    }
}

struct OpenAICompatibleCorrector {
    func correct(transcript: String, language: SupportedLanguage, configuration: OpenAICompatibleConfiguration) async throws -> String {
        guard transcript.isEmpty == false else {
            return transcript
        }

        return try await OpenAICompatibleChatClient().complete(
            configuration: configuration,
            systemPrompt: systemPrompt,
            userPrompt: """
            Target language preference: \(language.displayName)

            Transcript:
            \(transcript)
            """
        )
    }

    private var systemPrompt: String {
        """
        You are a transcript correction engine.
        You must be extremely conservative.

        Rules:
        1. Only fix obvious speech-recognition errors.
        2. Typical allowed fixes include Chinese homophone mistakes and English technical terms wrongly rendered in Chinese, such as 配森 -> Python and 杰森 -> JSON.
        3. Never rewrite, paraphrase, polish, summarize, translate, reorder, or delete content that already looks correct.
        4. If the input already looks correct, you must return it unchanged.
        5. Preserve wording, line breaks, punctuation, and spacing whenever they already look reasonable.
        6. Return only the corrected transcript text and nothing else.
        """
    }
}

struct OpenAICompatibleTranslator {
    func translate(
        transcript: String,
        sourceLanguage: SupportedLanguage,
        targetLanguage: SupportedLanguage,
        configuration: OpenAICompatibleConfiguration
    ) async throws -> String {
        guard transcript.isEmpty == false else {
            return transcript
        }

        guard sourceLanguage != targetLanguage else {
            return transcript
        }

        return try await OpenAICompatibleChatClient().complete(
            configuration: configuration,
            systemPrompt: systemPrompt,
            userPrompt: """
            Source language hint: \(sourceLanguage.displayName)
            Target language: \(targetLanguage.displayName)

            Transcript:
            \(transcript)
            """
        )
    }

    private var systemPrompt: String {
        """
        You are a real-time transcript translator.

        Rules:
        1. Translate faithfully into the requested target language.
        2. Never summarize, explain, add commentary, or omit information.
        3. Preserve meaning, tone, and line breaks whenever possible.
        4. Keep technical terms, code symbols, filenames, APIs, and product names unchanged when that is the correct translation behavior.
        5. If some words are already best left in the original language, keep them.
        6. Return only the translated text and nothing else.
        """
    }
}

private struct OpenAICompatibleChatClient {
    func complete(
        configuration: OpenAICompatibleConfiguration,
        systemPrompt: String,
        userPrompt: String
    ) async throws -> String {
        let endpoint = configuration.baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")

        let body = ChatCompletionRequest(
            model: configuration.model,
            temperature: 0,
            messages: [
                ChatMessage(role: "system", content: systemPrompt),
                ChatMessage(role: "user", content: userPrompt)
            ]
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200 ..< 300 ~= httpResponse.statusCode else {
            throw OpenAICompatibleCorrectorError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content, content.isEmpty == false else {
            throw OpenAICompatibleCorrectorError.emptyResponse
        }

        return content
    }
}

private struct ChatCompletionRequest: Encodable {
    let model: String
    let temperature: Double
    let messages: [ChatMessage]
}

private struct ChatMessage: Codable {
    let role: String
    let content: String
}

private struct ChatCompletionResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: ChatMessage
    }
}
