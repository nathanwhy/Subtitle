import AVFoundation
import Speech

enum SpeechRecognitionServiceError: LocalizedError {
    case recognizerUnavailable

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return "Speech recognizer is unavailable for the selected language."
        }
    }
}

final class SpeechRecognitionService {
    private let recognizer: SFSpeechRecognizer
    private let request = SFSpeechAudioBufferRecognitionRequest()
    private let stateQueue = DispatchQueue(label: "subtitle.speech.state")
    private let onPartialResult: @Sendable (String) -> Void
    private let onError: @Sendable (Error) -> Void
    private var recognitionTask: SFSpeechRecognitionTask?
    private var latestTranscript = ""
    private var suppressErrors = false

    init(
        language: SupportedLanguage,
        onPartialResult: @escaping @Sendable (String) -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) throws {
        guard let recognizer = SFSpeechRecognizer(locale: language.locale) else {
            throw SpeechRecognitionServiceError.recognizerUnavailable
        }

        self.recognizer = recognizer
        self.onPartialResult = onPartialResult
        self.onError = onError
    }

    func start() {
        stateQueue.sync {
            suppressErrors = false
            latestTranscript = ""
        }
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let transcript = result.bestTranscription.formattedString
                self.stateQueue.async {
                    self.latestTranscript = transcript
                }
                self.onPartialResult(transcript)
            }

            if let error {
                let shouldSuppress = self.stateQueue.sync {
                    self.suppressErrors
                }
                if shouldSuppress == false {
                    self.onError(error)
                }
            }
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        request.append(buffer)
    }

    func finish() async -> String {
        stateQueue.sync {
            suppressErrors = true
        }
        request.endAudio()
        try? await Task.sleep(for: .milliseconds(900))

        let transcript = stateQueue.sync {
            latestTranscript
        }

        recognitionTask?.cancel()
        recognitionTask = nil
        return transcript
    }

    func cancel() {
        stateQueue.sync {
            suppressErrors = true
        }
        request.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
    }
}
