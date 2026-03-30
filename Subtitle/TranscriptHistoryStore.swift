import Foundation

struct TranscriptHistoryStore {
    private let fileManager: FileManager
    private let fileURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let appFolder = baseURL.appendingPathComponent(Bundle.main.bundleIdentifier ?? "Subtitle", isDirectory: true)
        self.fileURL = appFolder.appendingPathComponent("transcripts.json", isDirectory: false)
    }

    func load() throws -> [TranscriptSession] {
        guard fileManager.fileExists(atPath: fileURL.path()) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let sessions = try decoder.decode([TranscriptSession].self, from: data)
        return sessions.sorted { $0.endedAt > $1.endedAt }
    }

    func save(_ sessions: [TranscriptSession]) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(sessions.sorted { $0.endedAt > $1.endedAt })
        try data.write(to: fileURL, options: .atomic)
    }
}
