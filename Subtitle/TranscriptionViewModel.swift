import CoreGraphics
import Foundation
import Speech
import Combine

@MainActor
final class TranscriptionViewModel: ObservableObject {
    @Published var selectedLanguage: SupportedLanguage = .english {
        didSet {
            if translationTargetLanguage == selectedLanguage {
                translationTargetLanguage = SupportedLanguage.defaultTranslationTarget(excluding: selectedLanguage)
            }
            saveSettings()
        }
    }
    @Published var llmCorrectionEnabled = false {
        didSet { saveSettings() }
    }
    @Published var liveTranslationEnabled = false {
        didSet {
            if liveTranslationEnabled == false {
                cancelLiveTranslation(resetText: true)
            } else if isRunning {
                scheduleLiveTranslation(for: currentTranscript)
            }
            saveSettings()
        }
    }
    @Published var apiBaseURL = "https://api.openai.com/v1" {
        didSet { saveSettings() }
    }
    @Published var apiModel = "gpt-4o-mini" {
        didSet { saveSettings() }
    }
    @Published var apiKey = "" {
        didSet { saveSettings() }
    }
    @Published var translationTargetLanguage: SupportedLanguage = .chinese {
        didSet {
            if translationTargetLanguage == selectedLanguage {
                translationTargetLanguage = SupportedLanguage.defaultTranslationTarget(excluding: selectedLanguage)
                return
            }
            if isRunning {
                scheduleLiveTranslation(for: currentTranscript)
            }
            saveSettings()
        }
    }
    @Published var floatingOverlayEnabled = false {
        didSet { saveSettings() }
    }
    @Published var floatingOverlayClickThroughEnabled = false {
        didSet { saveSettings() }
    }
    @Published var floatingOverlayShowsOriginal = true {
        didSet {
            ensureFloatingOverlayTrackVisibility()
            saveSettings()
        }
    }
    @Published var floatingOverlayShowsTranslation = true {
        didSet {
            ensureFloatingOverlayTrackVisibility()
            saveSettings()
        }
    }
    @Published var floatingOverlayOpacity = 0.88 {
        didSet { saveSettings() }
    }
    @Published var floatingOverlayFontScale = 1.0 {
        didSet { saveSettings() }
    }
    @Published var floatingOverlayLineCount = 3 {
        didSet { saveSettings() }
    }
    @Published var floatingOverlayLineWidth = 26 {
        didSet { saveSettings() }
    }
    @Published var currentTranscript = ""
    @Published var translatedTranscript = ""
    @Published var sessions: [TranscriptSession] = []
    @Published var isRunning = false
    @Published var isStopping = false
    @Published var isCorrectingWithLLM = false
    @Published var isTranslatingLive = false
    @Published var errorMessage: String?
    @Published var statusMessage: String?
    @Published var screenCapturePermissionGranted = CGPreflightScreenCaptureAccess()
    @Published var speechAuthorizationStatus = SFSpeechRecognizer.authorizationStatus()

    private let historyStore = TranscriptHistoryStore()
    private let corrector = OpenAICompatibleCorrector()
    private let translator = OpenAICompatibleTranslator()
    private let defaults = UserDefaults.standard
    private var liveCoordinator: LiveTranscriptionCoordinator?
    private var currentSessionStartedAt: Date?
    private var isRestoringSettings = false
    private var liveTranslationTask: Task<Void, Never>?
    private var liveTranslationRevision = 0

    var isBusy: Bool {
        isStopping || isCorrectingWithLLM || (isRunning == false && isTranslatingLive)
    }

    var speechAuthorizationGranted: Bool {
        speechAuthorizationStatus == .authorized
    }

    var speechAuthorizationDescription: String {
        switch speechAuthorizationStatus {
        case .authorized:
            return "Ready"
        case .denied:
            return "Permission denied in System Settings"
        case .restricted:
            return "Restricted by the system"
        case .notDetermined:
            return "Permission not requested"
        @unknown default:
            return "Unknown speech permission state"
        }
    }

    var translationTargetOptions: [SupportedLanguage] {
        SupportedLanguage.allCases.filter { $0 != selectedLanguage }
    }

    var overlayTranslationAvailable: Bool {
        liveTranslationEnabled || translatedTranscript.isEmpty == false
    }

    func load() async {
        loadSettings()
        refreshPermissions()

        do {
            sessions = try historyStore.load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func requestScreenCaptureAccess() {
        _ = CGRequestScreenCaptureAccess()
        screenCapturePermissionGranted = CGPreflightScreenCaptureAccess()
        if screenCapturePermissionGranted == false {
            statusMessage = "Grant Screen Recording access in System Settings before starting live transcription."
        }
    }

    func requestSpeechAuthorization() async {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { authorizationStatus in
                continuation.resume(returning: authorizationStatus)
            }
        }

        speechAuthorizationStatus = status
        if status != .authorized {
            statusMessage = "Speech recognition permission is required for live transcription."
        }
    }

    func startTranscription() async {
        guard isRunning == false, isBusy == false else { return }

        errorMessage = nil
        statusMessage = nil
        refreshPermissions()
        cancelLiveTranslation(resetText: true)

        if screenCapturePermissionGranted == false {
            statusMessage = "Screen Recording permission is required to capture system audio."
            return
        }

        if speechAuthorizationGranted == false {
            await requestSpeechAuthorization()
            guard speechAuthorizationGranted else { return }
        }

        currentTranscript = ""
        translatedTranscript = ""
        currentSessionStartedAt = Date()

        do {
            let coordinator = try LiveTranscriptionCoordinator(
                language: selectedLanguage,
                onPartialResult: { [weak self] text in
                    Task { @MainActor in
                        self?.handlePartialTranscript(text)
                    }
                },
                onError: { [weak self] error in
                    Task { @MainActor in
                        self?.handleRuntimeError(error)
                    }
                }
            )

            try await coordinator.start()
            liveCoordinator = coordinator
            isRunning = true
            statusMessage = "Listening to system audio."
        } catch {
            liveCoordinator = nil
            currentSessionStartedAt = nil
            errorMessage = error.localizedDescription
        }
    }

    func stopTranscription() async {
        guard isRunning, isStopping == false else { return }

        isStopping = true
        errorMessage = nil
        statusMessage = "Finalizing transcript..."

        let startedAt = currentSessionStartedAt ?? Date()
        let rawTranscript = await liveCoordinator?.stop() ?? currentTranscript
        liveCoordinator = nil
        isRunning = false
        isStopping = false
        currentSessionStartedAt = nil
        cancelLiveTranslation(resetText: false)

        let finalRawTranscript = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard finalRawTranscript.isEmpty == false else {
            currentTranscript = ""
            translatedTranscript = ""
            statusMessage = "No speech was recognized."
            return
        }

        currentTranscript = finalRawTranscript

        var correctedTranscript: String?
        if llmCorrectionEnabled {
            do {
                let configuration = try llmConfiguration()
                isCorrectingWithLLM = true
                statusMessage = "Running conservative LLM correction..."
                correctedTranscript = try await corrector.correct(
                    transcript: finalRawTranscript,
                    language: selectedLanguage,
                    configuration: configuration
                )
                currentTranscript = correctedTranscript ?? finalRawTranscript
            } catch {
                errorMessage = error.localizedDescription
                statusMessage = "Saved the raw transcript because LLM correction failed."
            }
            isCorrectingWithLLM = false
        }

        let finalTranscriptForDisplay = correctedTranscript ?? finalRawTranscript
        var finalTranslatedTranscript: String?
        if liveTranslationEnabled {
            do {
                let configuration = try llmConfiguration()
                isTranslatingLive = true
                statusMessage = "Running final translation..."
                finalTranslatedTranscript = try await translator.translate(
                    transcript: finalTranscriptForDisplay,
                    sourceLanguage: selectedLanguage,
                    targetLanguage: translationTargetLanguage,
                    configuration: configuration
                )
                translatedTranscript = finalTranslatedTranscript ?? ""
            } catch {
                translatedTranscript = ""
                errorMessage = error.localizedDescription
                statusMessage = "Saved the transcript without translation because LLM translation failed."
            }
            isTranslatingLive = false
        } else {
            translatedTranscript = ""
        }

        let session = TranscriptSession(
            id: UUID(),
            startedAt: startedAt,
            endedAt: Date(),
            language: selectedLanguage,
            rawText: finalRawTranscript,
            correctedText: correctedTranscript,
            llmEnabled: llmCorrectionEnabled && correctedTranscript != nil,
            llmModel: (llmCorrectionEnabled || liveTranslationEnabled) ? apiModel : nil,
            translatedText: finalTranslatedTranscript,
            translationLanguage: finalTranslatedTranscript == nil ? nil : translationTargetLanguage
        )

        sessions.insert(session, at: 0)

        do {
            try historyStore.save(sessions)
            statusMessage = "Transcript saved locally."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteSession(_ session: TranscriptSession) {
        sessions.removeAll { $0.id == session.id }

        do {
            try historyStore.save(sessions)
            statusMessage = "Transcript deleted."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleRuntimeError(_ error: Error) {
        cancelLiveTranslation(resetText: false)
        errorMessage = error.localizedDescription
        statusMessage = nil

        guard isRunning else { return }

        Task {
            await liveCoordinator?.cancel()
            liveCoordinator = nil
            isRunning = false
            isStopping = false
            currentSessionStartedAt = nil
        }
    }

    private func refreshPermissions() {
        screenCapturePermissionGranted = CGPreflightScreenCaptureAccess()
        speechAuthorizationStatus = SFSpeechRecognizer.authorizationStatus()
    }

    private func handlePartialTranscript(_ text: String) {
        currentTranscript = text
        scheduleLiveTranslation(for: text)
    }

    private func scheduleLiveTranslation(for transcript: String) {
        liveTranslationTask?.cancel()
        liveTranslationTask = nil

        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard liveTranslationEnabled, trimmedTranscript.isEmpty == false, translationTargetLanguage != selectedLanguage else {
            isTranslatingLive = false
            if liveTranslationEnabled == false || trimmedTranscript.isEmpty {
                translatedTranscript = ""
            }
            return
        }

        let configuration: OpenAICompatibleConfiguration
        do {
            configuration = try llmConfiguration()
        } catch {
            isTranslatingLive = false
            translatedTranscript = ""
            return
        }

        liveTranslationRevision += 1
        let revision = liveTranslationRevision
        let sourceLanguage = selectedLanguage
        let targetLanguage = translationTargetLanguage

        liveTranslationTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, Task.isCancelled == false else { return }

            await MainActor.run {
                guard self.liveTranslationRevision == revision else { return }
                self.isTranslatingLive = true
            }

            do {
                let translated = try await self.translator.translate(
                    transcript: trimmedTranscript,
                    sourceLanguage: sourceLanguage,
                    targetLanguage: targetLanguage,
                    configuration: configuration
                )

                guard Task.isCancelled == false else { return }

                await MainActor.run {
                    guard self.liveTranslationRevision == revision else { return }
                    self.translatedTranscript = translated
                    self.isTranslatingLive = false
                }
            } catch {
                await MainActor.run {
                    guard self.liveTranslationRevision == revision else { return }
                    self.isTranslatingLive = false
                }
            }
        }
    }

    private func cancelLiveTranslation(resetText: Bool) {
        liveTranslationTask?.cancel()
        liveTranslationTask = nil
        liveTranslationRevision += 1
        isTranslatingLive = false
        if resetText {
            translatedTranscript = ""
        }
    }

    private func ensureFloatingOverlayTrackVisibility() {
        if floatingOverlayShowsOriginal == false && floatingOverlayShowsTranslation == false {
            floatingOverlayShowsOriginal = true
        }
    }

    private func clampedFloatingOverlayOpacity(_ value: Double) -> Double {
        min(max(value, 0.55), 1)
    }

    private func clampedFloatingOverlayFontScale(_ value: Double) -> Double {
        min(max(value, 0.85), 1.7)
    }

    private func clampedFloatingOverlayLineCount(_ value: Int) -> Int {
        min(max(value, 1), 6)
    }

    private func clampedFloatingOverlayLineWidth(_ value: Int) -> Int {
        min(max(value, 12), 48)
    }

    private func llmConfiguration() throws -> OpenAICompatibleConfiguration {
        let trimmedBaseURL = apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = apiModel.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let baseURL = URL(string: trimmedBaseURL) else {
            throw OpenAICompatibleCorrectorError.invalidBaseURL
        }

        guard trimmedAPIKey.isEmpty == false, trimmedModel.isEmpty == false else {
            throw OpenAICompatibleCorrectorError.missingConfiguration
        }

        return OpenAICompatibleConfiguration(baseURL: baseURL, apiKey: trimmedAPIKey, model: trimmedModel)
    }

    private func loadSettings() {
        isRestoringSettings = true
        selectedLanguage = SupportedLanguage(rawValue: defaults.string(forKey: SettingsKey.language.rawValue) ?? "") ?? .english
        llmCorrectionEnabled = defaults.bool(forKey: SettingsKey.llmEnabled.rawValue)
        liveTranslationEnabled = defaults.bool(forKey: SettingsKey.liveTranslationEnabled.rawValue)
        apiBaseURL = defaults.string(forKey: SettingsKey.apiBaseURL.rawValue) ?? "https://api.openai.com/v1"
        apiModel = defaults.string(forKey: SettingsKey.apiModel.rawValue) ?? "gpt-4o-mini"
        apiKey = defaults.string(forKey: SettingsKey.apiKey.rawValue) ?? ""
        translationTargetLanguage = SupportedLanguage(rawValue: defaults.string(forKey: SettingsKey.translationTargetLanguage.rawValue) ?? "") ?? .chinese
        floatingOverlayEnabled = defaults.bool(forKey: SettingsKey.floatingOverlayEnabled.rawValue)
        floatingOverlayClickThroughEnabled = defaults.bool(forKey: SettingsKey.floatingOverlayClickThroughEnabled.rawValue)
        floatingOverlayShowsOriginal = defaults.object(forKey: SettingsKey.floatingOverlayShowsOriginal.rawValue) as? Bool ?? true
        floatingOverlayShowsTranslation = defaults.object(forKey: SettingsKey.floatingOverlayShowsTranslation.rawValue) as? Bool ?? true
        floatingOverlayOpacity = clampedFloatingOverlayOpacity(defaults.object(forKey: SettingsKey.floatingOverlayOpacity.rawValue) as? Double ?? 0.88)
        floatingOverlayFontScale = clampedFloatingOverlayFontScale(defaults.object(forKey: SettingsKey.floatingOverlayFontScale.rawValue) as? Double ?? 1.0)
        floatingOverlayLineCount = clampedFloatingOverlayLineCount(defaults.object(forKey: SettingsKey.floatingOverlayLineCount.rawValue) as? Int ?? 3)
        floatingOverlayLineWidth = clampedFloatingOverlayLineWidth(defaults.object(forKey: SettingsKey.floatingOverlayLineWidth.rawValue) as? Int ?? 26)
        if translationTargetLanguage == selectedLanguage {
            translationTargetLanguage = SupportedLanguage.defaultTranslationTarget(excluding: selectedLanguage)
        }
        ensureFloatingOverlayTrackVisibility()
        isRestoringSettings = false
    }

    private func saveSettings() {
        guard isRestoringSettings == false else { return }
        defaults.set(selectedLanguage.rawValue, forKey: SettingsKey.language.rawValue)
        defaults.set(llmCorrectionEnabled, forKey: SettingsKey.llmEnabled.rawValue)
        defaults.set(liveTranslationEnabled, forKey: SettingsKey.liveTranslationEnabled.rawValue)
        defaults.set(apiBaseURL, forKey: SettingsKey.apiBaseURL.rawValue)
        defaults.set(apiModel, forKey: SettingsKey.apiModel.rawValue)
        defaults.set(apiKey, forKey: SettingsKey.apiKey.rawValue)
        defaults.set(translationTargetLanguage.rawValue, forKey: SettingsKey.translationTargetLanguage.rawValue)
        defaults.set(floatingOverlayEnabled, forKey: SettingsKey.floatingOverlayEnabled.rawValue)
        defaults.set(floatingOverlayClickThroughEnabled, forKey: SettingsKey.floatingOverlayClickThroughEnabled.rawValue)
        defaults.set(floatingOverlayShowsOriginal, forKey: SettingsKey.floatingOverlayShowsOriginal.rawValue)
        defaults.set(floatingOverlayShowsTranslation, forKey: SettingsKey.floatingOverlayShowsTranslation.rawValue)
        defaults.set(clampedFloatingOverlayOpacity(floatingOverlayOpacity), forKey: SettingsKey.floatingOverlayOpacity.rawValue)
        defaults.set(clampedFloatingOverlayFontScale(floatingOverlayFontScale), forKey: SettingsKey.floatingOverlayFontScale.rawValue)
        defaults.set(clampedFloatingOverlayLineCount(floatingOverlayLineCount), forKey: SettingsKey.floatingOverlayLineCount.rawValue)
        defaults.set(clampedFloatingOverlayLineWidth(floatingOverlayLineWidth), forKey: SettingsKey.floatingOverlayLineWidth.rawValue)
    }

    private enum SettingsKey: String {
        case language = "subtitle.settings.language"
        case llmEnabled = "subtitle.settings.llmEnabled"
        case liveTranslationEnabled = "subtitle.settings.liveTranslationEnabled"
        case apiBaseURL = "subtitle.settings.apiBaseURL"
        case apiModel = "subtitle.settings.apiModel"
        case apiKey = "subtitle.settings.apiKey"
        case translationTargetLanguage = "subtitle.settings.translationTargetLanguage"
        case floatingOverlayEnabled = "subtitle.settings.floatingOverlayEnabled"
        case floatingOverlayClickThroughEnabled = "subtitle.settings.floatingOverlayClickThroughEnabled"
        case floatingOverlayShowsOriginal = "subtitle.settings.floatingOverlayShowsOriginal"
        case floatingOverlayShowsTranslation = "subtitle.settings.floatingOverlayShowsTranslation"
        case floatingOverlayOpacity = "subtitle.settings.floatingOverlayOpacity"
        case floatingOverlayFontScale = "subtitle.settings.floatingOverlayFontScale"
        case floatingOverlayLineCount = "subtitle.settings.floatingOverlayLineCount"
        case floatingOverlayLineWidth = "subtitle.settings.floatingOverlayLineWidth"
    }
}
