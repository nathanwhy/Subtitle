import AVFoundation

final class LiveTranscriptionCoordinator {
    private let speechRecognitionService: SpeechRecognitionService
    private let systemAudioCapture: SystemAudioCapture

    init(
        language: SupportedLanguage,
        onPartialResult: @escaping @Sendable (String) -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) throws {
        let speechRecognitionService = try SpeechRecognitionService(
            language: language,
            onPartialResult: onPartialResult,
            onError: onError
        )

        self.speechRecognitionService = speechRecognitionService
        self.systemAudioCapture = SystemAudioCapture(
            onBuffer: { buffer in
                speechRecognitionService.append(buffer)
            },
            onError: onError
        )
    }

    func start() async throws {
        speechRecognitionService.start()
        try await systemAudioCapture.start()
    }

    func stop() async -> String {
        await systemAudioCapture.stop()
        return await speechRecognitionService.finish()
    }

    func cancel() async {
        await systemAudioCapture.stop()
        speechRecognitionService.cancel()
    }
}
