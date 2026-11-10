import Foundation
import FoundationModels

enum Distribution {
    static let store = Bundle.main.object(forInfoDictionaryKey: "BigBrainDistribution") as? String == "store"

    static func engine() throws -> (executable: URL, args: [String], environment: [String: String]?) {
        if store {
            guard let source = Bundle.main.url(forResource: "brain", withExtension: "py"),
                  let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                throw BackendFailure(message: "Det lokala biblioteket kunde inte startas.")
            }
            let executable = Bundle.main.bundleURL.appendingPathComponent(
                "Contents/Frameworks/PythonRuntime.framework/Versions/A/bin/python3.12")
            let data = support.appendingPathComponent("BigBrain Studio", isDirectory: true)
            let env = ["BIGBRAIN_STORE": "1", "BIGBRAIN_AGENT_HOME": data.path,
                       "PATH": "/usr/bin:/bin", "PYTHONNOUSERSITE": "1", "LC_CTYPE": "UTF-8"]
            return (executable, ["-B", "-s", source.path], env)
        }
        guard let script = Bundle.main.url(forResource: "bigbrain", withExtension: nil) else {
            throw BackendFailure(message: "Appens lokala brygga saknas.")
        }
        return (script, [], nil)
    }

    static func stageImport(from folder: URL) throws -> URL {
        let fm = FileManager.default
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        let top = fm.temporaryDirectory.appendingPathComponent("bigbrain-import-" + UUID().uuidString)
        let destination = top.appendingPathComponent(folder.lastPathComponent, isDirectory: true)
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        let keys: Set<URLResourceKey> = [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey]
        do {
            guard let walk = fm.enumerator(at: folder, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) else {
                throw BackendFailure(message: "Mappen kunde inte läsas.")
            }
            let prefix = folder.path + "/"
            for case let file as URL in walk {
                let info = try file.resourceValues(forKeys: keys)
                if info.isSymbolicLink == true { walk.skipDescendants(); continue }
                guard file.path.hasPrefix(prefix) else { continue }
                let copy = destination.appendingPathComponent(String(file.path.dropFirst(prefix.count)))
                if info.isDirectory == true {
                    try fm.createDirectory(at: copy, withIntermediateDirectories: true)
                } else if info.isRegularFile == true {
                    try fm.copyItem(at: file, to: copy)
                }
            }
            return destination
        } catch {
            try? fm.removeItem(at: top)
            throw error
        }
    }
}

struct LocalPrompt: Decodable {
    let instructions: String
    let content: String
    let state: String
}

enum DeviceModel {
    static var status: CodexStatus {
        if #available(macOS 26.0, *), case .available = SystemLanguageModel.default.availability {
            return CodexStatus(ready: true, message: "Modell på enheten")
        }
        return CodexStatus(ready: false, message: "Apple Intelligence krävs för agentsvar")
    }

    static func run(_ input: Data?) async throws -> AgentReply {
        guard #available(macOS 26.0, *), case .available = SystemLanguageModel.default.availability else {
            throw BackendFailure(message: "Aktivera Apple Intelligence för att använda agentsvar på enheten.")
        }
        let prompt: LocalPrompt = try await Bridge.invoke(["local-prompt"], input: input)
        let session = LanguageModelSession(instructions: prompt.instructions)
        let result = try await session.respond(to: prompt.content)
        let text = result.content
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start <= end,
              let reply = try? JSONSerialization.jsonObject(with: Data(text[start...end].utf8)) as? [String: String] else {
            throw BackendFailure(message: "Modellen gav inget strukturerat svar. Försök med en kortare fråga.")
        }
        return try await Bridge.invoke(["local-finish"], input: Bridge.object(["state": prompt.state, "reply": reply]))
    }
}
