import SwiftUI

struct FloatingSubtitleOverlayView: View {
    @ObservedObject var viewModel: TranscriptionViewModel

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.06, green: 0.08, blue: 0.11).opacity(viewModel.floatingOverlayOpacity),
                            Color(red: 0.12, green: 0.15, blue: 0.18).opacity(viewModel.floatingOverlayOpacity)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)

            VStack(alignment: .leading, spacing: 18) {
                header
                content
            }
            .padding(22)
        }
        .shadow(color: .black.opacity(0.28), radius: 26, y: 14)
        .padding(10)
        .frame(minWidth: 680, minHeight: minimumOverlayHeight)
    }

    private var header: some View {
        HStack(alignment: .center) {
            HStack(spacing: 8) {
                Circle()
                    .fill(viewModel.isRunning ? Color(red: 0.38, green: 0.89, blue: 0.58) : Color.white.opacity(0.42))
                    .frame(width: 9, height: 9)

                Text(viewModel.isRunning ? "Live Subtitle Overlay" : "Overlay Preview")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.92))
            }

            Spacer()

            Text(statusLine)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.56))
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.floatingOverlayShowsOriginal && viewModel.floatingOverlayShowsTranslation {
            HStack(alignment: .top, spacing: 18) {
                overlayColumn(
                    title: "Original • \(viewModel.selectedLanguage.displayName)",
                    text: originalText,
                    isPlaceholder: originalTextIsPlaceholder
                )

                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 1)

                overlayColumn(
                    title: "Translation • \(viewModel.translationTargetLanguage.displayName)",
                    text: translatedText,
                    isPlaceholder: translatedTextIsPlaceholder
                )
            }
        } else if viewModel.floatingOverlayShowsOriginal {
            overlayColumn(
                title: "Original • \(viewModel.selectedLanguage.displayName)",
                text: originalText,
                isPlaceholder: originalTextIsPlaceholder
            )
        } else {
            overlayColumn(
                title: "Translation • \(viewModel.translationTargetLanguage.displayName)",
                text: translatedText,
                isPlaceholder: translatedTextIsPlaceholder
            )
        }
    }

    private func overlayColumn(title: String, text: String, isPlaceholder: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.58))

            Text(text)
                .font(.system(size: 16 * viewModel.floatingOverlayFontScale, weight: .regular, design: .rounded))
                .foregroundStyle(isPlaceholder ? Color.white.opacity(0.46) : Color.white.opacity(0.98))
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineSpacing(5)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var originalText: String {
        let trimmed = viewModel.currentTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty == false {
            return formattedSubtitleText(trimmed)
        }
        if viewModel.isRunning {
            return "Listening for system audio..."
        }
        return "Start live transcription to show the source subtitle stream here."
    }

    private var translatedText: String {
        let trimmed = viewModel.translatedTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty == false {
            return formattedSubtitleText(trimmed)
        }
        if viewModel.liveTranslationEnabled == false {
            return "Enable real-time translation to show the translated subtitle stream here."
        }
        if viewModel.isTranslatingLive {
            return "Translating..."
        }
        if viewModel.isRunning {
            return "Waiting for enough transcript to translate..."
        }
        return "Start live transcription to show the translated subtitle stream here."
    }

    private var originalTextIsPlaceholder: Bool {
        viewModel.currentTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var translatedTextIsPlaceholder: Bool {
        viewModel.translatedTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var statusLine: String {
        if viewModel.floatingOverlayShowsOriginal && viewModel.floatingOverlayShowsTranslation {
            return "\(viewModel.selectedLanguage.displayName) -> \(viewModel.translationTargetLanguage.displayName)"
        }
        if viewModel.floatingOverlayShowsOriginal {
            return viewModel.selectedLanguage.displayName
        }
        return viewModel.translationTargetLanguage.displayName
    }

    private var minimumOverlayHeight: CGFloat {
        let lineHeight = 34.0 * viewModel.floatingOverlayFontScale
        let contentHeight = (Double(viewModel.floatingOverlayLineCount) * lineHeight) + 120
        return max(180, contentHeight)
    }

    private func formattedSubtitleText(_ text: String) -> String {
        let rawLines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .flatMap { wrapLine(String($0), maxLineWidth: effectiveLineWidth) }

        let visibleLines = Array(rawLines.suffix(viewModel.floatingOverlayLineCount))
        return visibleLines.joined(separator: "\n")
    }

    private var effectiveLineWidth: Double {
        let singleColumnBonus = (viewModel.floatingOverlayShowsOriginal && viewModel.floatingOverlayShowsTranslation) ? 0.0 : 10.0
        return max(8, (Double(viewModel.floatingOverlayLineWidth) + singleColumnBonus) / viewModel.floatingOverlayFontScale)
    }

    private func wrapLine(_ line: String, maxLineWidth: Double) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return [""]
        }

        let phrases = splitIntoPhrases(trimmed)
        var wrapped: [String] = []
        var current = ""

        for phrase in phrases {
            let normalizedPhrase = normalizeWhitespace(in: phrase)
            guard normalizedPhrase.isEmpty == false else { continue }

            let separator = needsSpaceBetween(current, normalizedPhrase) ? " " : ""
            let candidate = current.isEmpty ? normalizedPhrase : current + separator + normalizedPhrase

            if visualWidth(of: candidate) <= maxLineWidth {
                current = candidate
                continue
            }

            if current.isEmpty == false {
                wrapped.append(current)
            }

            if visualWidth(of: normalizedPhrase) <= maxLineWidth {
                current = normalizedPhrase
            } else {
                let pieces = wrapLongPhrase(normalizedPhrase, maxLineWidth: maxLineWidth)
                wrapped.append(contentsOf: pieces.dropLast())
                current = pieces.last ?? ""
            }
        }

        if current.isEmpty == false {
            wrapped.append(current)
        }

        return wrapped
    }

    private func splitIntoPhrases(_ text: String) -> [String] {
        var phrases: [String] = []
        var current = ""

        for character in text {
            current.append(character)
            if strongBreakCharacters.contains(character) || softBreakCharacters.contains(character) {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty == false {
                    phrases.append(trimmed)
                }
                current = ""
            }
        }

        let remainder = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if remainder.isEmpty == false {
            phrases.append(remainder)
        }

        return phrases.isEmpty ? [text] : phrases
    }

    private func wrapLongPhrase(_ text: String, maxLineWidth: Double) -> [String] {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        if words.count > 1 {
            var lines: [String] = []
            var current = ""

            for word in words {
                let separator = current.isEmpty ? "" : " "
                let candidate = current + separator + word
                if visualWidth(of: candidate) <= maxLineWidth {
                    current = candidate
                } else {
                    if current.isEmpty == false {
                        lines.append(current)
                    }

                    if visualWidth(of: word) <= maxLineWidth {
                        current = word
                    } else {
                        let chunks = chunkCharacters(in: word, maxLineWidth: maxLineWidth)
                        lines.append(contentsOf: chunks.dropLast())
                        current = chunks.last ?? ""
                    }
                }
            }

            if current.isEmpty == false {
                lines.append(current)
            }

            return lines
        }

        return chunkCharacters(in: text, maxLineWidth: maxLineWidth)
    }

    private func chunkCharacters(in text: String, maxLineWidth: Double) -> [String] {
        guard maxLineWidth > 0 else { return [text] }

        var chunks: [String] = []
        var current = ""

        for character in text {
            let candidate = current + String(character)
            if current.isEmpty == false && visualWidth(of: candidate) > maxLineWidth {
                chunks.append(current)
                current = String(character)
            } else {
                current = candidate
            }
        }

        if current.isEmpty == false {
            chunks.append(current)
        }

        return chunks
    }

    private func normalizeWhitespace(in text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private func needsSpaceBetween(_ lhs: String, _ rhs: String) -> Bool {
        guard let lhsLast = lhs.last, let rhsFirst = rhs.first else {
            return false
        }
        return lhsLast.isASCIIWordCharacter && rhsFirst.isASCIIWordCharacter
    }

    private func visualWidth(of text: String) -> Double {
        text.reduce(into: 0) { width, character in
            width += character.displayWidth
        }
    }

    private var strongBreakCharacters: Set<Character> {
        [".", "!", "?", ";", ":", "。", "！", "？", "；", "："]
    }

    private var softBreakCharacters: Set<Character> {
        [",", "，", "、"]
    }
}

private extension Character {
    var isASCIIWordCharacter: Bool {
        unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "_"
        }
    }

    var displayWidth: Double {
        if isWhitespace {
            return 0.35
        }

        if isASCIIWordCharacter {
            return isUppercaseASCII ? 0.72 : 0.62
        }

        if isCJKPunctuation {
            return 0.78
        }

        if unicodeScalars.allSatisfy({ $0.properties.isIdeographic || $0.properties.isUnifiedIdeograph }) {
            return 1.0
        }

        if unicodeScalars.allSatisfy(\.isASCII) {
            return 0.52
        }

        return 1.0
    }

    private var isUppercaseASCII: Bool {
        unicodeScalars.allSatisfy { scalar in
            CharacterSet.uppercaseLetters.contains(scalar) && scalar.isASCII
        }
    }

    private var isCJKPunctuation: Bool {
        ["。", "，", "！", "？", "；", "：", "、", "（", "）", "「", "」", "『", "』", "《", "》"].contains(self)
    }
}
