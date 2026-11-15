import Foundation
import FoundationModels
import Security

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
        return try await runPreparedAgent(input) { prompt in
            let session = LanguageModelSession(instructions: prompt.instructions)
            return try await session.respond(to: prompt.content).content
        }
    }
}

private func runPreparedAgent(_ input: Data?, respond: (LocalPrompt) async throws -> String) async throws -> AgentReply {
    let prompt: LocalPrompt = try await Bridge.invoke(["local-prompt"], input: input)
    let text = try await respond(prompt)
    guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start <= end,
          let reply = try? JSONSerialization.jsonObject(with: Data(text[start...end].utf8)) as? [String: String] else {
        throw BackendFailure(message: "Modellen gav inget strukturerat svar. Försök med en kortare fråga.")
    }
    return try await Bridge.invoke(["local-finish"], input: Bridge.object(["state": prompt.state, "reply": reply]))
}


struct CustomModel {
    let url: URL
    let id: String

    static var enabled: Bool { UserDefaults.standard.bool(forKey: "customModelEnabled") }

    init(endpoint: String, id: String) throws {
        let input = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parts = URLComponents(string: input), let url = parts.url,
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil,
              parts.scheme == "https" || parts.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host),
              !model.isEmpty else {
            throw BackendFailure(message: "Enter a model ID and an HTTPS endpoint. HTTP is supported on localhost.")
        }
        let base = url.path.isEmpty || url.path == "/" ? url.appendingPathComponent("v1") : url
        self.url = base.path.hasSuffix("/chat/completions") ? base : base.appendingPathComponent("chat/completions")
        self.id = model
    }

    static func configured() throws -> Self {
        try Self(endpoint: UserDefaults.standard.string(forKey: "customModelEndpoint") ?? "",
                 id: UserDefaults.standard.string(forKey: "customModelID") ?? "")
    }

    private var keychainItem: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "BigBrain custom model",
         kSecAttrAccount as String: (Bundle.main.bundleIdentifier ?? "BigBrain") + "|" + url.absoluteString]
    }

    func setKey(_ key: String) throws {
        let status: OSStatus
        if key.isEmpty {
            status = SecItemDelete(keychainItem as CFDictionary)
        } else {
            let data = Data(key.utf8)
            let update = SecItemUpdate(keychainItem as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            if update == errSecItemNotFound {
                var item = keychainItem
                item[kSecValueData as String] = data
                status = SecItemAdd(item as CFDictionary, nil)
            } else {
                status = update
            }
        }
        guard status == errSecSuccess || key.isEmpty && status == errSecItemNotFound else {
            throw BackendFailure(message: "BigBrain could not update the model key in Keychain (\(status)).")
        }
    }

    private func key() throws -> String? {
        var query = keychainItem
        query[kSecReturnData as String] = true
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw BackendFailure(message: "BigBrain could not read the model key from Keychain (\(status)).")
        }
        return String(decoding: data, as: UTF8.self)
    }

    func complete(instructions: String, content: String) async throws -> String {
        struct Response: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String? }
                let message: Message
            }
            let choices: [Choice]
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = try key() { request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": id, "stream": false,
            "messages": [["role": "system", "content": instructions], ["role": "user", "content": content]]
        ])
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        let session = URLSession(configuration: config, delegate: RefuseModelRedirects(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, result) = try await session.data(for: request)
        guard let http = result as? HTTPURLResponse else { throw BackendFailure(message: "The model returned no HTTP response.") }
        guard (200..<300).contains(http.statusCode) else {
            throw BackendFailure(message: "The configured model returned HTTP \(http.statusCode). Check the endpoint, model ID and key.")
        }
        guard let content = try? JSONDecoder().decode(Response.self, from: data).choices.first?.message.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BackendFailure(message: "The model returned no text.")
        }
        return content
    }

    func run(_ input: Data?) async throws -> AgentReply {
        try await runPreparedAgent(input) { prompt in
            try await complete(instructions: prompt.instructions, content: prompt.content)
        }
    }
}

private final class RefuseModelRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
