import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = TranscriptionViewModel()
    @StateObject private var overlayController = FloatingSubtitleWindowController()

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.95, blue: 0.91),
                    Color(red: 0.90, green: 0.94, blue: 0.95)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    HStack(alignment: .top, spacing: 20) {
                        VStack(alignment: .leading, spacing: 20) {
                            controlsCard
                            llmCard
                            overlayCard
                        }
                        .frame(maxWidth: 340)

                        VStack(alignment: .leading, spacing: 20) {
                            liveTranscriptCard
                            savedSessionsCard
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(16)
            }
        }
        .frame(minWidth: 1120, minHeight: 780)
        .task {
            await viewModel.load()
            overlayController.setVisible(viewModel.floatingOverlayEnabled, using: viewModel)
        }
        .onAppear {
            overlayController.bind(to: viewModel)
        }
        .onChange(of: viewModel.floatingOverlayEnabled) { isVisible in
            overlayController.setVisible(isVisible, using: viewModel)
        }
        .alert("Transcription Error", isPresented: errorBinding) {
            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Subtitle Studio")
                .font(.system(size: 34, weight: .bold, design: .rounded))

            Text("Capture system audio, generate live transcription, and optionally run conservative LLM correction before saving locally.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(Color(red: 0.13, green: 0.52, blue: 0.56).opacity(0.12))
                .frame(width: 120, height: 120)
                .offset(x: 30, y: -30)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var controlsCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Controls")
                .font(.title3.weight(.semibold))

            Picker("Language", selection: $viewModel.selectedLanguage) {
                ForEach(SupportedLanguage.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .pickerStyle(.segmented)
            .disabled(viewModel.isRunning)

            VStack(alignment: .leading, spacing: 10) {
                permissionRow(
                    title: "Screen Audio",
                    detail: viewModel.screenCapturePermissionGranted ? "Ready" : "Screen Recording permission required",
                    isGranted: viewModel.screenCapturePermissionGranted
                )

                permissionRow(
                    title: "Speech",
                    detail: viewModel.speechAuthorizationDescription,
                    isGranted: viewModel.speechAuthorizationGranted
                )
            }

            if !viewModel.screenCapturePermissionGranted {
                Button("Request Screen Recording Access") {
                    viewModel.requestScreenCaptureAccess()
                }
                .buttonStyle(.bordered)
            }

            if !viewModel.speechAuthorizationGranted {
                Button("Request Speech Access") {
                    Task {
                        await viewModel.requestSpeechAuthorization()
                    }
                }
                .buttonStyle(.bordered)
            }

            Divider()

            Button {
                if viewModel.isRunning {
                    Task {
                        await viewModel.stopTranscription()
                    }
                } else {
                    Task {
                        await viewModel.startTranscription()
                    }
                }
            } label: {
                HStack {
                    Image(systemName: viewModel.isRunning ? "stop.circle.fill" : "waveform.circle.fill")
                    Text(viewModel.isRunning ? "Stop & Save" : "Start Live Transcription")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(viewModel.isRunning ? .red : Color(red: 0.13, green: 0.52, blue: 0.56))
            .disabled(viewModel.isBusy)

            if let statusMessage = viewModel.statusMessage, !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var llmCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("OpenAI-Compatible LLM")
                    .font(.title3.weight(.semibold))

                Text("Use the configured model for conservative transcript correction and optional real-time translation.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Toggle(isOn: $viewModel.llmCorrectionEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Conservative Correction")
                        .font(.subheadline.weight(.semibold))

                    Text("Only correct obvious ASR mistakes. Never rewrite, polish, or delete valid content.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .disabled(viewModel.isRunning)

            Toggle(isOn: $viewModel.liveTranslationEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Real-Time Translation")
                        .font(.subheadline.weight(.semibold))

                    Text("Translate the live transcript into English, Chinese, or Japanese while recording.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            Picker("Translate To", selection: $viewModel.translationTargetLanguage) {
                ForEach(viewModel.translationTargetOptions) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!viewModel.liveTranslationEnabled)

            TextField("API Base URL", text: $viewModel.apiBaseURL)
                .textFieldStyle(.roundedBorder)
                .disabled(viewModel.isRunning)

            TextField("Model", text: $viewModel.apiModel)
                .textFieldStyle(.roundedBorder)
                .disabled(viewModel.isRunning)

            SecureField("API Key", text: $viewModel.apiKey)
                .textFieldStyle(.roundedBorder)
                .disabled(viewModel.isRunning)

            Text("Suggested base URL format: `https://api.openai.com/v1` or any OpenAI-compatible endpoint root.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(22)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var liveTranscriptCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Live Transcript")
                        .font(.title3.weight(.semibold))

                    Text(viewModel.isRunning ? "Streaming from system audio" : "Last captured transcription")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if viewModel.isRunning {
                    Label("Listening", systemImage: "waveform")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(red: 0.13, green: 0.52, blue: 0.56).opacity(0.14))
                        .clipShape(Capsule())
                }

                if viewModel.isTranslatingLive {
                    Label("Translating", systemImage: "globe")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.16))
                        .clipShape(Capsule())
                } else if viewModel.isCorrectingWithLLM {
                    Label("LLM Refining", systemImage: "sparkles")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.16))
                        .clipShape(Capsule())
                }
            }

            Group {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Transcript")
                            .font(.headline)

                        if viewModel.currentTranscript.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("No transcript yet")
                                    .font(.headline)

                                Text("Start live transcription after granting Screen Recording and Speech permissions.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 160, alignment: .leading)
                        } else {
                            ScrollView {
                                Text(viewModel.currentTranscript)
                                    .font(.system(size: 18, weight: .medium, design: .rounded))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                            .frame(minHeight: 180)
                        }
                    }

                    if viewModel.liveTranslationEnabled {
                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Translation • \(viewModel.translationTargetLanguage.displayName)")
                                .font(.headline)

                            if viewModel.translatedTranscript.isEmpty {
                                Text("Live translation will appear here once enough transcript is available.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
                            } else {
                                ScrollView {
                                    Text(viewModel.translatedTranscript)
                                        .font(.system(size: 18, weight: .medium, design: .rounded))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .textSelection(.enabled)
                                }
                                .frame(minHeight: 160)
                            }
                        }
                    }
                }
            }
            .padding(16)
            .background(Color.black.opacity(0.78))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .padding(16)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var savedSessionsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Saved Sessions")
                    .font(.title3.weight(.semibold))

                Spacer()

                Text("\(viewModel.sessions.count)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if viewModel.sessions.isEmpty {
                ContentUnavailableView(
                    "No Saved Transcripts",
                    systemImage: "text.badge.plus",
                    description: Text("Completed transcription sessions are stored locally by default and can be deleted here.")
                )
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(viewModel.sessions) { session in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.headline)

                                    Text(sessionMetaLine(for: session))
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Button(role: .destructive) {
                                    viewModel.deleteSession(session)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .buttonStyle(.borderless)
                            }

                            Text(session.displayText)
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)

                            if let translatedText = session.translatedText,
                               let translationLanguage = session.translationLanguage {
                                Divider()

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Translation • \(translationLanguage.displayName)")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.secondary)

                                    Text(translatedText)
                                        .font(.body)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        .padding(16)
                        .background(Color.black.opacity(0.78))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
            }
        }
        .padding(16)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func permissionRow(title: String, detail: String, isGranted: Bool) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Circle()
                .fill(isGranted ? Color.green : Color.orange)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var overlayCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Floating Overlay")
                    .font(.title3.weight(.semibold))

                Text("Show a resizable always-on-top subtitle panel for original and translated text.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Toggle("Show Floating Overlay", isOn: $viewModel.floatingOverlayEnabled)
                .toggleStyle(.switch)

            Toggle("Show Original Column", isOn: $viewModel.floatingOverlayShowsOriginal)
                .toggleStyle(.switch)

            Toggle("Show Translation Column", isOn: $viewModel.floatingOverlayShowsTranslation)
                .toggleStyle(.switch)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Overlay Opacity")
                    Spacer()
                    Text("\(Int(viewModel.floatingOverlayOpacity * 100))%")
                        .foregroundStyle(.secondary)
                }
                Slider(value: $viewModel.floatingOverlayOpacity, in: 0.55 ... 1)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Text Scale")
                    Spacer()
                    Text(String(format: "%.2fx", viewModel.floatingOverlayFontScale))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $viewModel.floatingOverlayFontScale, in: 0.85 ... 1.7)
            }

            Stepper(value: $viewModel.floatingOverlayLineCount, in: 1 ... 6) {
                HStack {
                    Text("Subtitle Lines")
                    Spacer()
                    Text("\(viewModel.floatingOverlayLineCount)")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(22)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func sessionMetaLine(for session: TranscriptSession) -> String {
        var parts = [session.language.displayName]
        parts.append(session.llmEnabled ? "LLM corrected" : "Raw transcript")
        if let translationLanguage = session.translationLanguage {
            parts.append("Translated to \(translationLanguage.displayName)")
        }
        return parts.joined(separator: " • ")
    }

    private var cardBackground: some ShapeStyle {
        .regularMaterial.opacity(0.9)
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { newValue in
                if !newValue {
                    viewModel.errorMessage = nil
                }
            }
        )
    }
}
