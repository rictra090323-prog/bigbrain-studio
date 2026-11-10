import Foundation

struct MobileCapture: Codable, Identifiable, Sendable {
    static let fileExtension = "bbcapture"
    static let textLimit = 65_536
    static let fileLimit = 524_288

    let version: Int
    let id: UUID
    let text: String

    var title: String {
        text.split(whereSeparator: \.isNewline).first.map { String($0.prefix(72)) } ?? "Anteckning"
    }

    func validate() throws {
        guard version == 1,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !text.utf8.contains(0) else { throw CaptureQueueError.invalidText }
        guard text.utf8.count <= Self.textLimit else { throw CaptureQueueError.tooLong }
    }
}

struct SavedCapture: Identifiable, Sendable {
    let capture: MobileCapture
    let file: URL

    var id: UUID { capture.id }
}

enum CaptureQueueError: LocalizedError {
    case invalidText, tooLong, invalidFile

    var errorDescription: String? {
        switch self {
        case .invalidText: "Skriv en anteckning med vanlig text."
        case .tooLong: "Anteckningen är för lång för snabbfångst. Dela upp den i flera anteckningar."
        case .invalidFile: "En sparad anteckning gick inte att läsa."
        }
    }
}

struct CaptureQueue {
    let directory: URL

    static func local() throws -> CaptureQueue {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        return CaptureQueue(directory: support.appendingPathComponent("BigBrainCaptures", isDirectory: true))
    }

    func save(_ input: String) throws -> SavedCapture {
        let capture = MobileCapture(version: 1, id: UUID(), text: input.trimmingCharacters(in: .whitespacesAndNewlines))
        try capture.validate()
        var folder = directory
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        var options: Data.WritingOptions = [.atomic]
        #if os(iOS)
        var backup = URLResourceValues()
        backup.isExcludedFromBackup = true
        try folder.setResourceValues(backup)
        options.insert(.completeFileProtection)
        #endif
        let file = url(for: capture.id)
        try JSONEncoder().encode(capture).write(to: file, options: options)
        return SavedCapture(capture: capture, file: file)
    }

    func load() throws -> (entries: [SavedCapture], unreadable: Int) {
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(at: directory,
                                                                includingPropertiesForKeys: [.contentModificationDateKey])
        } catch CocoaError.fileReadNoSuchFile {
            return ([], 0)
        }
        let newestFirst = files.filter { $0.pathExtension == MobileCapture.fileExtension }.map { file in
            (file: file, date: (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
        }.sorted { $0.date > $1.date }

        var entries: [SavedCapture] = []
        var unreadable = 0
        for item in newestFirst {
            do {
                let handle = try FileHandle(forReadingFrom: item.file)
                defer { try? handle.close() }
                let data = try handle.read(upToCount: MobileCapture.fileLimit + 1) ?? Data()
                guard data.count <= MobileCapture.fileLimit else { throw CaptureQueueError.invalidFile }
                let capture = try JSONDecoder().decode(MobileCapture.self, from: data)
                try capture.validate()
                guard url(for: capture.id).lastPathComponent == item.file.lastPathComponent else {
                    throw CaptureQueueError.invalidFile
                }
                entries.append(SavedCapture(capture: capture, file: item.file))
            } catch {
                unreadable += 1
            }
        }
        return (entries, unreadable)
    }

    func remove(_ id: UUID) throws {
        try FileManager.default.removeItem(at: url(for: id))
    }

    private func url(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString.lowercased()).appendingPathExtension(MobileCapture.fileExtension)
    }
}
