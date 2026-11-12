import AppKit
import SwiftUI
import UniformTypeIdentifiers

typealias LocalState<Value> = SwiftUI.State<Value>

private let base = Color(red: 0.035, green: 0.047, blue: 0.102)
private let panel = Color(red: 0.101, green: 0.127, blue: 0.213)
let inset = Color(red: 0.059, green: 0.082, blue: 0.153)
private let line = Color.white.opacity(0.085)
private let muted = Color(red: 0.67, green: 0.70, blue: 0.77)
private let ice = Color(red: 0.74, green: 0.77, blue: 1)
private let lime = Color(red: 0.57, green: 0.96, blue: 1)

enum Section: String, CaseIterable, Identifiable {
    case atlas = "Atlas", radar = "Radar", search = "Bibliotek", inbox = "Inkorg", review = "Granska", writing = "Skrivcoach", skills = "Skills", settings = "Inställningar"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .atlas: "point.3.connected.trianglepath.dotted"
        case .radar: "dot.radiowaves.left.and.right"
        case .search: "magnifyingglass"
        case .inbox: "tray"
        case .review: "rectangle.split.2x1"
        case .writing: "pencil.line"
        case .skills: "square.stack.3d.up"
        case .settings: "slider.horizontal.3"
        }
    }
}

struct Hit: Codable, Identifiable, Hashable, Sendable {
    let id: String, path: String, file: String, title: String, kind: String, excerpt: String, match: String
    var preview: String? = nil
}

struct NoteAppearance: Codable, Equatable {
    enum Accent: String, Codable, CaseIterable {
        case standard = "Isblå", ocean = "Havsblå", lavender = "Lavendel"
        case mint = "Mint", peach = "Aprikos", rose = "Rosa"

        var tint: Color {
            switch self {
            case .standard: lime
            case .ocean: Color(red: 0.53, green: 0.73, blue: 1)
            case .lavender: Color(red: 0.78, green: 0.68, blue: 1)
            case .mint: Color(red: 0.57, green: 0.93, blue: 0.73)
            case .peach: Color(red: 1, green: 0.76, blue: 0.48)
            case .rose: Color(red: 1, green: 0.63, blue: 0.77)
            }
        }
    }

    enum Symbol: String, Codable, CaseIterable {
        case document = "Dokument", study = "Studier", meeting = "Möte"
        case tasks = "Uppgifter", idea = "Idé", journal = "Dagbok"

        var icon: String {
            switch self {
            case .document: "doc.text"
            case .study: "graduationcap"
            case .meeting: "person.2"
            case .tasks: "checklist"
            case .idea: "lightbulb"
            case .journal: "book.closed"
            }
        }
    }

    var accent = Accent.standard
    var symbol = Symbol.document
}

struct Note: Decodable {
    let path: String, file: String, body: String, revision: String
}

struct Change: Decodable, Identifiable {
    let id: String, path: String, reason: String, source: String, created: String, status: String
}

struct ChangeDetail: Decodable {
    let path: String, status: String, diff: String, replacement: String, conflict: Bool
    let linkConflict: Bool?

    enum CodingKeys: String, CodingKey {
        case path, status, diff, replacement, conflict
        case linkConflict = "link_conflict"
    }
}

struct Profile: Decodable {
    let language: String, defaults: [String], examples: [Feedback]
}

struct Feedback: Decodable, Identifiable {
    let id: String, genre: String, before: String, after: String, rule: String, created: String
}

struct Config: Decodable {
    let vault: String, codex: String, qmd: String, auto: Bool, data: String, vaultReady: Bool, native: Bool, learning: Bool
}

struct Dashboard: Decodable {
    let config: Config, notes: Int, inbox: Int, skills: Int, proposals: [Change], latest: [Hit]
    let vectors: Bool, vectorAvailable: Bool, radar: AgentReply
}

struct AgentReply: Decodable {
    var answer: String?
    var rule: String?
    var proposal: String?
    var sources: [Hit]?
    var status: String?
    var mode: String?
    var date: String?
}

struct ContextPack: Decodable { let text: String }
struct ExtractedSource: Decodable { let body: String }
struct CodexStatus: Decodable { let ready: Bool, message: String }
struct Confirmation: Decodable {}
struct ImportedLibrary: Decodable { let library: String, imported: Int }
struct ImportedNote: Decodable { let note: Note, title: String, created: Bool }

struct BackendFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum Bridge {
    static func invoke<T: Decodable & Sendable>(_ args: [String], input: Data? = nil, as type: T.Type = T.self) async throws -> T {
        let launch = try Distribution.engine()
        return try await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            let temp = fm.temporaryDirectory.appendingPathComponent("bigbrain-\(UUID().uuidString)", isDirectory: true)
            try fm.createDirectory(at: temp, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            defer { try? fm.removeItem(at: temp) }
            let inputURL = temp.appendingPathComponent("input")
            let outURL = temp.appendingPathComponent("output")
            let logURL = temp.appendingPathComponent("error")
            try Data().write(to: inputURL)
            try Data().write(to: outURL)
            try Data().write(to: logURL)
            let stdIn = try FileHandle(forUpdating: inputURL)
            defer { try? stdIn.close() }
            let stdOut = try FileHandle(forUpdating: outURL)
            defer { try? stdOut.close() }
            let stdErr = try FileHandle(forUpdating: logURL)
            defer { try? stdErr.close() }
            // Open file handles survive unlinking, so an interruption leaves no named payload files.
            try fm.removeItem(at: temp)
            if let input { try stdIn.write(contentsOf: input) }
            try stdIn.seek(toOffset: 0)
            let process = Process()
            process.executableURL = launch.executable
            process.arguments = launch.args + args
            process.environment = launch.environment
            process.standardInput = stdIn
            process.standardOutput = stdOut
            process.standardError = stdErr
            try process.run()
            process.waitUntilExit()
            try stdOut.seek(toOffset: 0)
            let output = try stdOut.readToEnd() ?? Data()
            if process.terminationStatus != 0 {
                let message = (try? JSONSerialization.jsonObject(with: output) as? [String: String])?["error"]
                try stdErr.seek(toOffset: 0)
                let fallback = try stdErr.readToEnd().flatMap { String(data: $0, encoding: .utf8) }?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw BackendFailure(message: message ?? fallback.flatMap { $0.isEmpty ? nil : $0 } ?? "BigBrain kunde inte slutföra åtgärden.")
            }
            do {
                return try JSONDecoder().decode(T.self, from: output)
            } catch {
                throw BackendFailure(message: "BigBrain kunde inte läsa svaret. \(error.localizedDescription)")
            }
        }.value
    }

    static func object(_ fields: [String: Any]) -> Data? {
        try? JSONSerialization.data(withJSONObject: fields)
    }
}

enum AtlasSearchState {
    case searching
    case results([Hit])
    case failed
}

@MainActor
final class BrainModel: ObservableObject {
    @Published var section = Section.atlas
    @Published var dashboard: Dashboard?
    @Published var codex: CodexStatus?
    @Published var query = ""
    @Published var hits: [Hit] = []
    @Published private var atlasSearch: (term: String, state: AtlasSearchState)?
    @Published var selected: Hit?
    @Published var note: Note?
    @Published var reply: AgentReply?
    @Published private(set) var editorHit: Hit?
    private(set) var editorCitation: StudioCitation?
    @Published private(set) var editorCommandRequest = 0
    @Published private(set) var librarySearchRequest = 0
    @Published private(set) var pinnedNotes: Set<String> = []
    @Published private var noteAppearances: [String: NoteAppearance] = [:]
    @Published var showingCapture = false
    @Published var showingTranscription = false
    @Published var error: String?
    @Published var toast = ""
    @Published var running = false
    @Published var searching = false
    @Published var profile: Profile?
    @Published var language = "sv"
    @Published var selectedChange: Change?
    @Published var detail: ChangeDetail?
    @Published var decidingChangeID: String?
    @Published var vaultInput = ""
    @Published var qmdInput = ""
    @Published var codexInput = ""
    @Published var auto = false
    @Published var vectorBusy = false
    @Published var atlas: AtlasSnapshot?
    @Published var atlasBusy = false
    @Published var importing = false
    @Published var learningEnabled = true

    private var lastOpened: (id: String, date: Date)?
    private var atlasGeneration = 0
    private var atlasSearchGeneration = 0
    private var recentAtlasKey: String? { activeVault.map { "atlasRecent:" + $0 } }

    private func rememberAtlasItem(_ hit: Hit) {
        guard hit.kind == "note" || hit.kind == "inbox", let key = recentAtlasKey else { return }
        let previous = UserDefaults.standard.stringArray(forKey: key) ?? []
        UserDefaults.standard.set(Array(([hit.id] + previous.filter { $0 != hit.id }).prefix(10)), forKey: key)
    }

    private var generation = 0
    private var refreshGeneration = 0
    private var changeGeneration = 0
    private var activeVault: String?
    private var libraryGeneration = 0
    private var pinnedNotesKey: String? { activeVault.map { "libraryPinned:" + $0 } }
    private var noteAppearancesKey: String? { activeVault.map { "noteAppearances:" + $0 } }
    private var started = false
    private var timer: Timer?
    private var ticking = false

    func start() {
        guard !started else { return }
        started = true
        Task {
            await refresh()
            if let config = dashboard?.config { read(config) }
            codex = Distribution.store ? DeviceModel.status : try? await Bridge.invoke(["codex-status"])
            await tick()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                await self.refresh(quiet: true)
                await self.tick()
            }
        }
    }

    func refresh(force: Bool = false, quiet: Bool = false) async {
        refreshGeneration += 1
        let request = refreshGeneration
        do {
            let result: Dashboard = try await Bridge.invoke([force ? "index" : "dashboard"])
            guard request == refreshGeneration else { return }
            observeVault(result.config.vault)
            dashboard = result
        } catch {
            if request == refreshGeneration && !quiet { self.error = error.localizedDescription }
        }
    }

    private func observeVault(_ vault: String) {
        defer {
            if activeVault != vault {
                activeVault = vault
                if let key = pinnedNotesKey { pinnedNotes = Set(UserDefaults.standard.stringArray(forKey: key) ?? []) }
                noteAppearances = noteAppearancesKey.flatMap { UserDefaults.standard.data(forKey: $0) }.flatMap {
                    try? JSONDecoder().decode([String: NoteAppearance].self, from: $0)
                } ?? [:]
            }
        }
        guard let activeVault, activeVault != vault else { return }
        libraryGeneration += 1
        generation += 1
        atlasGeneration += 1
        changeGeneration += 1
        dismissAtlasSearch()
        lastOpened = nil
        query = ""
        hits = []
        searching = false
        atlas = nil
        atlasBusy = false
        selected = nil
        note = nil
        reply = nil
        selectedChange = nil
        detail = nil
        closeEditor()
        dashboard = nil
    }

    func read(_ config: Config) {
        if let activeVault, activeVault != config.vault { refreshGeneration += 1 }
        observeVault(config.vault)
        vaultInput = config.vault
        codexInput = config.codex
        qmdInput = config.qmd
        auto = config.auto
        learningEnabled = config.learning
    }

    func show(_ target: Section) {
        closeEditor()
        guard section != target else { return }
        section = target
        dismissAtlasSearch()
        generation += 1
        selected = nil
        note = nil
        hits = []
        searching = false
        if target == .skills { query = "" }
        if target == .writing {
            Task { await loadStyle() }
        } else if target == .search || target == .skills || target == .inbox {
            Task { await search() }
        } else if target == .review {
            Task { await refresh() }
        }
    }

    func search() async {
        let key = generation + 1
        generation = key
        let scope = section == .skills ? "skills" : section == .inbox ? "inbox" : Distribution.store ? "note" : "all"
        let term = section == .inbox ? "" : query
        let browsingLibrary = section == .search && term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        searching = true
        do {
            let args = ["search", "--limit", "25", "--scope", scope]
            let result: [Hit] = try await Bridge.invoke(browsingLibrary ? ["library"] : args + ["--fast", "--", term])
            guard generation == key else { return }
            hits = browsingLibrary ? result.sorted {
                let order = $0.title.localizedStandardCompare($1.title)
                return order == .orderedSame ? $0.path < $1.path : order == .orderedAscending
            } : result
            searching = false
            if dashboard?.vectors == true && (scope == "all" || scope == "note") && !term.isEmpty && !Task.isCancelled {
                let refined: [Hit] = try await Bridge.invoke(args + ["--", term])
                if generation == key && !Task.isCancelled { hits = refined }
            }
        } catch {
            guard generation == key else { return }
            searching = false
            self.error = error.localizedDescription
        }
    }

    func searchFromAtlas() {
        query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        reply = nil
        show(.search)
    }

    var atlasSearchTerm: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    func atlasSearchState(for term: String) -> AtlasSearchState? {
        guard atlasSearch?.term == term else { return nil }
        return atlasSearch?.state
    }

    func searchAtlasSuggestions(for term: String) async {
        guard !Task.isCancelled, section == .atlas, !term.isEmpty, atlasSearchTerm == term else { return }
        atlasSearchGeneration += 1
        let request = atlasSearchGeneration
        atlasSearch = nil
        do {
            try await Task.sleep(for: .milliseconds(280))
        } catch { return }
        guard request == atlasSearchGeneration, !Task.isCancelled, atlasSearchTerm == term else { return }

        atlasSearch = (term, .searching)
        let state: AtlasSearchState
        do {
            let scope = Distribution.store ? "note" : "all"
            let hits: [Hit] = try await Bridge.invoke(["search", "--limit", "25", "--scope", scope,
                                                       "--fast", "--", term])
            state = .results(hits)
        } catch {
            state = .failed
        }
        guard request == atlasSearchGeneration, !Task.isCancelled, atlasSearchTerm == term else { return }
        atlasSearch = (term, state)
    }

    func dismissAtlasSearch() {
        atlasSearchGeneration += 1
        atlasSearch = nil
    }

    func togglePin(_ hit: Hit) {
        guard let key = pinnedNotesKey, hit.kind == "note" else { return }
        let pinned = pinnedNotes.insert(hit.id).inserted
        if !pinned { pinnedNotes.remove(hit.id) }
        UserDefaults.standard.set(pinnedNotes.sorted(), forKey: key)
        BrainHaptics.action()
        notify(pinned ? "Anteckningen är fäst" : "Anteckningen är lossad")
    }

    func appearance(for hit: Hit) -> NoteAppearance {
        noteAppearances[hit.id] ?? NoteAppearance()
    }

    func setAppearance(_ appearance: NoteAppearance, for hit: Hit) {
        guard let key = noteAppearancesKey, hit.kind == "note", appearance != self.appearance(for: hit) else { return }
        noteAppearances[hit.id] = appearance == NoteAppearance() ? nil : appearance
        if let data = try? JSONEncoder().encode(noteAppearances) { UserDefaults.standard.set(data, forKey: key) }
        BrainHaptics.selection()
    }

    func closeAtlasDetail() {
        selected = nil
        note = nil
        Task { await loadAtlas() }
    }

    func loadAtlas() async {
        guard let key = recentAtlasKey else { return }
        let recent = UserDefaults.standard.stringArray(forKey: key) ?? []
        atlasGeneration += 1
        let generation = atlasGeneration
        atlasBusy = true
        do {
            let arguments = ["atlas", "--focus=" + (selected?.id ?? "")]
                + (Distribution.store ? ["--notes-only"] : [])
                + recent.prefix(10).map { "--recent=" + $0 }
            let view: AtlasSnapshot = try await Bridge.invoke(arguments)
            guard generation == atlasGeneration else { return }
            atlas = view
            atlasBusy = false
        } catch {
            guard generation == atlasGeneration else { return }
            atlasBusy = false
            self.error = error.localizedDescription
        }
    }

    func adopt(_ folder: URL) {
        guard !importing else { return }
        importing = true
        Task {
            defer { importing = false }
            do {
                let staged: URL?
                if Distribution.store {
                    staged = try await Task.detached { try Distribution.stageImport(from: folder) }.value
                } else { staged = nil }
                defer { if let staged { try? FileManager.default.removeItem(at: staged.deletingLastPathComponent()) } }
                let library: ImportedLibrary = try await Bridge.invoke(["adopt", "--from=" + (staged ?? folder).path])
                lastOpened = nil
                await refresh(force: true)
                if let config = dashboard?.config { read(config) }
                show(.atlas)
                await loadAtlas()
                notify(library.imported == 0 ? "Ditt BigBrain-bibliotek är skapat" : "Importerade \(library.imported) Markdown-filer")
            } catch { self.error = error.localizedDescription }
        }
    }

    func importWord(_ file: URL) {
        importNote(from: file, arguments: ["import-word", "--", file.lastPathComponent], limit: 10_000_000,
                   sizeError: "Word-filen får vara högst 10 MB.",
                   messages: ("Word-anteckningen är importerad", "Word-filen är redan importerad"))
    }

    func choosePhoneCapture() {
        guard !importing else { return }
        let panel = NSOpenPanel()
        panel.title = "Importera från iPhone"
        panel.prompt = "Importera"
        panel.message = "Välj en BigBrain-anteckning (.bbcapture) som du har skickat från iPhone."
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "bbcapture") ?? .data]
        guard panel.runModal() == .OK, let file = panel.url else { return }
        guard file.pathExtension.lowercased() == "bbcapture" else {
            error = "Välj en BigBrain-anteckning i formatet .bbcapture."
            return
        }
        importNote(from: file, arguments: ["import-phone-capture"], limit: 524_288,
                   sizeError: "Fångstfilen får vara högst 512 KB.",
                   messages: ("Anteckningen från iPhone är importerad", "Anteckningen finns redan i biblioteket"))
    }

    private func importNote(from file: URL, arguments: [String], limit: Int, sizeError: String,
                            messages: (created: String, existing: String)) {
        guard !importing else { return }
        importing = true
        Task {
            defer { importing = false }
            do {
                let data = try await Task.detached {
                    let scoped = file.startAccessingSecurityScopedResource()
                    defer { if scoped { file.stopAccessingSecurityScopedResource() } }
                    guard try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                        throw BackendFailure(message: "Välj en vanlig fil.")
                    }
                    let handle = try FileHandle(forReadingFrom: file)
                    defer { try? handle.close() }
                    let data = try handle.read(upToCount: limit + 1) ?? Data()
                    guard data.count <= limit else {
                        throw BackendFailure(message: sizeError)
                    }
                    return data
                }.value
                let result: ImportedNote = try await Bridge.invoke(arguments, input: data)
                await refresh()
                show(.search)
                query = result.title
                await search()
                select(Hit(id: "note:" + result.note.path, path: result.note.path, file: result.note.file,
                           title: result.title, kind: "note", excerpt: "", match: "text"), train: false)
                notify(result.created ? messages.created : messages.existing)
            } catch { self.error = error.localizedDescription }
        }
    }

    func select(_ hit: Hit, train: Bool = true) {
        selected = hit
        note = nil
        let prior = lastOpened
        if train { lastOpened = (hit.id, .now) }
        let library = libraryGeneration
        Task {
            do {
                let loaded: Note
                if hit.kind == "skill" {
                    let body = try String(contentsOfFile: hit.file, encoding: .utf8)
                    loaded = Note(path: hit.path, file: hit.file, body: body, revision: "")
                } else {
                    loaded = try await Bridge.invoke(["note", "--", hit.path])
                }
                guard library == libraryGeneration else { return }
                if selected?.id == hit.id {
                    note = loaded
                    rememberAtlasItem(hit)
                }
                if train, let prior, prior.id != hit.id, Date.now.timeIntervalSince(prior.date) < 600 {
                    let _: Confirmation = try await Bridge.invoke(["activate", prior.id, hit.id])
                }
                if section == .atlas && selected?.id == hit.id { await loadAtlas() }
            } catch {
                if library == libraryGeneration && selected?.id == hit.id { self.error = error.localizedDescription }
            }
        }
    }

    func notify(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(for: .seconds(3.5))
            if toast == message { toast = "" }
        }
    }

    func copy(_ text: String, label: String = "Kopierat") {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        notify(label)
    }

    func copyContext() {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        Task {
            do {
                let pack: ContextPack = try await Bridge.invoke(["context", term, "--limit", "5"])
                if pack.text.isEmpty { notify("Inga källor att kopiera"); return }
                copy(pack.text, label: "Källpaketet är kopierat")
            } catch { self.error = error.localizedDescription }
        }
    }

    func extract(_ source: String) async -> String? {
        do {
            let result: ExtractedSource = try await Bridge.invoke(["extract", source])
            return result.body
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    func capture(title: String, body: String, source: String, inbox: Bool, appearance: NoteAppearance? = nil) async -> Bool {
        do {
            let args = ["capture", "--source=\(source)"] + (inbox ? [] : ["--note"]) + ["--", title, "-"]
            let created: Note = try await Bridge.invoke(args, input: Data(body.utf8))
            await refresh()
            show(inbox ? .inbox : .search)
            if !inbox { query = title }
            await search()
            let kind = inbox ? "inbox" : "note"
            let hit = Hit(id: "note:" + created.path, path: created.path, file: created.file, title: title,
                          kind: kind, excerpt: "", match: "text")
            if !inbox, let appearance { setAppearance(appearance, for: hit) }
            select(hit, train: false)
            notify(inbox ? "Sparat i inkorgen" : "Sparat i biblioteket")
            if auto && inbox { Task { await tick() } }
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func openEditor(for hit: Hit, citation: StudioCitation? = nil) {
        guard hit.kind == "note", !hit.path.hasPrefix("Codex Skills/"),
              let note, note.path == hit.path else { return }
        dismissAtlasSearch()
        editorCitation = citation
        editorHit = hit
    }

    func openSearchCommand() {
        if editorHit == nil {
            show(.search)
            librarySearchRequest += 1
        } else {
            editorCommandRequest += 1
        }
    }

    func closeEditor() {
        guard editorHit != nil else { return }
        editorHit = nil
        editorCitation = nil
    }

    func acceptStudioEdit(_ updated: Note, replacing expected: Note) {
        if note?.file == expected.file && note?.revision == expected.revision {
            note = updated
            if section == .search { Task { await search() } }
        }
    }

    func run(_ mode: String, query: String = "", path: String = "", before: String = "", after: String = "",
             genre: String = "") async -> AgentReply? {
        guard !running else { return nil }
        running = true
        defer { running = false }
        let library = libraryGeneration
        do {
            let fields = ["mode": mode, "query": query, "path": path, "language": language,
                          "before": before, "after": after, "genre": genre]
            let input = Bridge.object(fields)
            let result: AgentReply = Distribution.store
                ? try await DeviceModel.run(input)
                : try await Bridge.invoke(["agent"], input: input)
            guard library == libraryGeneration else { return nil }
            if mode != "learn" && mode != "write" { reply = result }
            if result.proposal != nil { await refresh(); notify("Nytt ändringsförslag") }
            return result
        } catch {
            if library == libraryGeneration { self.error = error.localizedDescription }
            return nil
        }
    }

    func tick() async {
        guard !ticking, !running else { return }
        ticking = true
        defer { ticking = false }
        do {
            let result: AgentReply = try await Bridge.invoke(["auto"])
            if result.status == "complete" || result.status == "error" { await refresh() }
        } catch { self.error = error.localizedDescription }
    }

    func openChange(_ change: Change) {
        changeGeneration += 1
        let request = changeGeneration
        selectedChange = change
        detail = nil
        Task {
            do {
                let result: ChangeDetail = try await Bridge.invoke(["proposal", change.id])
                if request == changeGeneration { detail = result }
            } catch {
                if request == changeGeneration { self.error = error.localizedDescription }
            }
        }
    }

    func decide(_ change: Change, accept: Bool) {
        guard decidingChangeID == nil else { return }
        decidingChangeID = change.id
        Task {
            defer { decidingChangeID = nil }
            do {
                let result: ChangeDetail = try await Bridge.invoke([accept ? "apply" : "dismiss", change.id])
                await refresh()
                if selectedChange?.id == change.id {
                    changeGeneration += 1
                    selectedChange = dashboard?.proposals.first { $0.id == change.id }
                    detail = result
                }
                notify(result.status == "accepted" ? "Uppdaterat i biblioteket" : "Förslaget avvisades")
            } catch {
                if selectedChange?.id == change.id { openChange(change) }
                self.error = error.localizedDescription
            }
        }
    }

    func stageLink(from note: Note, to candidate: Hit) async {
        let originalSection = section
        let library = libraryGeneration
        do {
            let change: Change = try await Bridge.invoke(["propose-link", "--", note.path, note.revision, candidate.path])
            await refresh()
            guard library == libraryGeneration else { return }
            guard section == originalSection, self.note?.path == note.path,
                  self.note?.revision == note.revision else {
                notify("Länkförslaget är sparat i Granska")
                return
            }
            show(.review)
            openChange(change)
        } catch {
            if library == libraryGeneration { self.error = error.localizedDescription }
        }
    }

    func loadStyle() async {
        do { profile = try await Bridge.invoke(["style", language]) }
        catch { self.error = error.localizedDescription }
    }

    func learn(before: String, after: String, genre: String, rule: String) async -> Bool {
        do {
            profile = try await Bridge.invoke(["learn"], input: Bridge.object([
                "language": language, "genre": genre, "before": before, "after": after, "rule": rule,
            ]))
            notify("Skrivprofilen har uppdaterats")
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func forget(_ item: Feedback) {
        Task {
            do {
                let _: Confirmation = try await Bridge.invoke(["unlearn", item.id])
                await loadStyle()
                notify("Regeln har tagits bort")
            } catch { self.error = error.localizedDescription }
        }
    }

    func saveSettings() {
        Task {
            do {
                let config: Config = try await Bridge.invoke(["configure"], input: Bridge.object([
                    "vault": vaultInput, "codex": codexInput, "qmd": qmdInput, "auto": auto, "learning": learningEnabled,
                ]))
                read(config)
                await refresh()
                codex = Distribution.store ? DeviceModel.status : try? await Bridge.invoke(["codex-status"])
                notify("Inställningarna är sparade")
                if config.auto { await tick() }
            } catch { self.error = error.localizedDescription }
        }
    }

    func install() {
        Task {
            do {
                let _: Confirmation = try await Bridge.invoke(["install"])
                await refresh(force: true)
                notify("Codex-bryggan är installerad för nya chattar")
            } catch { self.error = error.localizedDescription }
        }
    }

    func vectors() {
        Task {
            guard !vectorBusy else { return }
            vectorBusy = true
            defer { vectorBusy = false }
            do {
                let _: Confirmation = try await Bridge.invoke(["vectors"])
                await refresh()
                notify("Vektorindexet är klart")
            } catch { self.error = error.localizedDescription }
        }
    }

    func reveal(_ relative: String) {
        Task {
            do {
                let saved: Note = try await Bridge.invoke(["note", "--", relative])
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: saved.file)])
            } catch { self.error = error.localizedDescription }
        }
    }
}

struct SmallLabel: View {
    let text: String
    var tint = muted
    var body: some View {
        Text(text.uppercased()).font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(1.7).foregroundStyle(tint)
    }
}

struct Badge: View {
    let text: String
    var tint = ice
    var body: some View {
        Text(text).font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(tint).padding(.horizontal, 8).padding(.vertical, 5)
            .background(tint.opacity(0.10), in: Capsule())
    }
}

struct ActionButton: View {
    let title: String
    var icon: String? = nil
    var primary = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let icon { Image(systemName: icon).font(.system(size: 11, weight: .semibold)) }
                Text(title).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(primary ? Color.white : Color.white.opacity(0.88))
            .padding(.vertical, 9).padding(.horizontal, 12)
            .brainGlass(Capsule(), interactive: true, tint: primary ? Color.blue.opacity(0.55) : nil)
        }
        .buttonStyle(.plain)
    }
}

enum BrainHaptics {
    static func selection() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    static func action() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }
}

struct WorkspaceTitle: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title).font(.system(size: 48, weight: .medium))
            .tracking(-3.4).accessibilityAddTraits(.isHeader)
    }
}

private struct NoteActionBar<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 7) { buttons }
        } else {
            buttons
        }
    }

    private var buttons: some View {
        HStack(spacing: 7) { content }
    }
}

struct BrainMark: View {
    var size: CGFloat = 36
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28).fill(lime)
            Image(systemName: "sparkle").font(.system(size: size * 0.58, weight: .bold))
                .rotationEffect(.degrees(11)).foregroundStyle(base)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct RadarGraphic: View {
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width * 0.66, y: size.height * 0.52)
            let radius = min(size.width * 0.42, size.height * 0.56)
            for index in 1...5 {
                let r = radius * Double(index) / 5
                let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
                context.stroke(Path(ellipseIn: rect), with: .color(ice.opacity(index == 5 ? 0.25 : 0.14)), lineWidth: 1)
            }
            for index in 0..<12 {
                let angle = Double(index) * .pi / 6
                var ray = Path()
                ray.move(to: center)
                ray.addLine(to: CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle)))
                context.stroke(ray, with: .color(ice.opacity(0.10)), lineWidth: 1)
            }
            let angles = [-1.04, -0.40, 0.75, 2.24, 3.55]
            let ranges = [0.83, 0.58, 0.67, 0.51, 0.92]
            var route = Path()
            for i in angles.indices {
                let p = CGPoint(x: center.x + radius * ranges[i] * cos(angles[i]),
                                y: center.y + radius * ranges[i] * sin(angles[i]))
                if i == 0 { route.move(to: p) } else { route.addLine(to: p) }
                let dot = Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6))
                context.fill(dot, with: .color(i == 0 || i == 3 ? lime : ice))
            }
            context.stroke(route, with: .color(lime.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            var axis = Path()
            axis.move(to: center)
            axis.addLine(to: CGPoint(x: center.x + radius * 0.86, y: center.y - radius * 0.52))
            context.stroke(axis, with: .color(lime.opacity(0.65)), lineWidth: 1)
            context.fill(Path(ellipseIn: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8)), with: .color(lime))
        }
        .accessibilityHidden(true)
    }
}

struct Panel<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(17).frame(maxWidth: .infinity, alignment: .leading)
            .background(panel, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(line))
    }
}

struct StatCard: View {
    let title: String
    let number: Int
    let icon: String
    var tint = ice
    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SmallLabel(text: title)
                    Spacer()
                    Image(systemName: icon).font(.system(size: 13)).foregroundStyle(tint)
                }
                Text(number.formatted()).font(.system(size: 29, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white)
            }
        }
    }
}

struct EmptyPanel: View {
    let icon: String, title: String, detail: String
    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: icon).font(.system(size: 23, weight: .light)).foregroundStyle(ice)
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(detail).font(.system(size: 12)).foregroundStyle(muted).multilineTextAlignment(.center)
        }
        .padding(23).frame(maxWidth: .infinity, minHeight: 115)
        .background(inset, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(line))
    }
}

struct Sidebar: View {
    @ObservedObject var model: BrainModel
    private let studioSections: [Section] = [.atlas, .search, .inbox, .review, .settings]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 9) {
                BrainMark()
                VStack(alignment: .leading, spacing: 3) {
                    Text("BigBrain").font(.system(size: 16, weight: .semibold))
                    SmallLabel(text: "Studio", tint: ice)
                }
            }
            .padding(.horizontal, 6)
            VStack(alignment: .leading, spacing: 5) {
                SmallLabel(text: "Arbetsyta").padding(.horizontal, 9).padding(.bottom, 6)
                ForEach(Distribution.store ? studioSections : Section.allCases) { section in
                    Button {
                        model.show(section)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: section.icon)
                                .font(.system(size: 13, weight: .medium)).frame(width: 16)
                            Text(section.rawValue).font(.system(size: 13, weight: model.section == section ? .semibold : .medium))
                            Spacer(minLength: 0)
                            if section == .review, let pending = model.dashboard?.proposals.filter({ $0.status == "pending" }).count, pending > 0 {
                                Text(String(pending)).font(.system(size: 10, design: .monospaced)).foregroundStyle(lime)
                            }
                        }
                        .foregroundStyle(model.section == section ? lime : muted)
                        .padding(.horizontal, 10).padding(.vertical, 9)
                        .background(model.section == section ? lime.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(model.section == section ? .isSelected : [])
                }
                if Distribution.store {
                    Menu("Verktyg") {
                        ForEach([Section.radar, .writing, .skills]) { section in
                            Button(section.rawValue) { model.show(section) }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .foregroundStyle(muted)
                    .padding(.horizontal, 9)
                }
            }
            Spacer()
            VStack(alignment: .leading, spacing: 9) {
                SmallLabel(text: "System")
                HStack(spacing: 7) {
                    Circle().fill(model.dashboard?.config.vaultReady == true ? lime : Color.orange)
                        .frame(width: 6, height: 6)
                    Text(model.dashboard?.config.native == true ? "Eget bibliotek" :
                         model.dashboard?.config.vaultReady == true ? "Importkälla" : "Bibliotek")
                }
                if !Distribution.store {
                    HStack(spacing: 7) {
                        Circle().fill(model.codex?.ready == true ? ice : Color.gray).frame(width: 6, height: 6)
                        Text(model.codex?.ready == true ? "Codex anslutet" : "Codex")
                    }
                }
            }
            .font(.system(size: 11)).foregroundStyle(muted)
            .padding(.horizontal, 9).padding(.bottom, 3)
        }
        .padding(.horizontal, 11).padding(.top, 18).padding(.bottom, 17)
        .frame(width: 157)
        .brainGlass(RoundedRectangle(cornerRadius: 24))
        .padding(.leading, 12).padding(.top, 36).padding(.bottom, 12)
    }
}

struct Header: View {
    @ObservedObject var model: BrainModel
    var body: some View {
        HStack(spacing: 12) {
            if model.section != .atlas && model.section != .search {
                Label(model.section.rawValue, systemImage: model.section.icon).font(.system(size: 13, weight: .medium))
            }
            Spacer()
            if model.section != .atlas && model.section != .search {
                ActionButton(title: "Sök  ⌘K", icon: "magnifyingglass") { model.show(.search) }
            }
            if #available(macOS 26.0, *) {
                ActionButton(title: "Transkribera", icon: "waveform") { model.showingTranscription = true }
            }
            ActionButton(title: "Fånga  ⌘N", icon: "plus", primary: true) { model.showingCapture = true }
        }
        .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 8)
    }
}

struct RadarView: View {
    @ObservedObject var model: BrainModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 19) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 17).fill(LinearGradient(colors: [
                        Color(red: 0.11, green: 0.12, blue: 0.20),
                        Color(red: 0.20, green: 0.21, blue: 0.34),
                    ], startPoint: .topLeading, endPoint: .bottomTrailing))
                    RadarGraphic().frame(width: 365).frame(maxWidth: .infinity, alignment: .trailing)
                        .clipped()
                    VStack(alignment: .leading, spacing: 13) {
                        HStack(spacing: 6) {
                            Circle().fill(lime).frame(width: 6, height: 6)
                            SmallLabel(text: "Källradar   /   BigBrain", tint: lime)
                        }
                        Text("Vad förändras\ni din kunskap?")
                            .font(.system(size: 37, weight: .medium, design: .serif))
                            .lineSpacing(-3).fixedSize(horizontal: false, vertical: true)
                        Text("Fånga en källa, följ beläggen och pröva nästa slutsats.")
                            .font(.system(size: 12)).foregroundStyle(muted)
                        ActionButton(title: "Utforska biblioteket", icon: "arrow.up.right", primary: true) { model.show(.search) }
                    }
                    .padding(24)
                }
                .frame(minHeight: 223)
                .clipShape(RoundedRectangle(cornerRadius: 17))
                .overlay(RoundedRectangle(cornerRadius: 17).stroke(ice.opacity(0.17)))
                HStack(spacing: 11) {
                    StatCard(title: "Anteckningar", number: model.dashboard?.notes ?? 0, icon: "doc.text")
                    StatCard(title: "Skills", number: model.dashboard?.skills ?? 0, icon: "square.stack.3d.up")
                    StatCard(title: "I inkorgen", number: model.dashboard?.inbox ?? 0, icon: "tray")
                    StatCard(title: "Att granska", number: model.dashboard?.proposals.filter { $0.status == "pending" }.count ?? 0,
                             icon: "rectangle.split.2x1", tint: lime)
                }
                HStack(alignment: .top, spacing: 13) {
                    Panel {
                        VStack(alignment: .leading, spacing: 13) {
                            HStack {
                                SmallLabel(text: "Senaste signal")
                                Spacer()
                                Badge(text: model.dashboard?.config.auto == true ? "AUTO PÅ" : "PÅ BEGÄRAN",
                                      tint: model.dashboard?.config.auto == true ? lime : ice)
                            }
                            if let radar = model.dashboard?.radar, let answer = radar.answer, !answer.isEmpty {
                                AnswerView(text: answer, sources: radar.sources ?? [], model: model)
                                if radar.proposal != nil {
                                    ActionButton(title: "Visa granskningskö", icon: "arrow.right") { model.show(.review) }
                                }
                            } else {
                                Text("Leta efter glapp i biblioteket").font(.system(size: 16, weight: .semibold))
                                Text("Agenten kan kontrollera länkar och jämföra belägg. Eventuella ändringar hamnar i granskningskön.")
                                    .font(.system(size: 12)).foregroundStyle(muted)
                                    .fixedSize(horizontal: false, vertical: true)
                                ActionButton(title: model.running ? "Arbetar…" : "Kör kunskapskontroll", icon: "scope") {
                                    Task {
                                        if await model.run("lint") != nil { model.show(.search) }
                                    }
                                }.disabled(model.running)
                            }
                        }
                    }
                    Panel {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                SmallLabel(text: "Inkorg")
                                Spacer()
                                ActionButton(title: "Visa alla", icon: "arrow.right") { model.show(.inbox) }
                            }
                            if let items = model.dashboard?.latest, !items.isEmpty {
                                ForEach(items.prefix(3)) { hit in
                                    Button {
                                        model.show(.inbox)
                                        model.select(hit)
                                    } label: {
                                        HStack {
                                            Image(systemName: "doc.text").foregroundStyle(ice)
                                            Text(hit.title).lineLimit(2)
                                            Spacer()
                                            Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(muted)
                                        }
                                        .font(.system(size: 12)).padding(.vertical, 4)
                                    }.buttonStyle(.plain)
                                }
                            } else {
                                Text("Inkorgen är tom.").font(.system(size: 14, weight: .medium))
                                Text("Lägg in en anteckning eller ett källutdrag för att se vad det tillför.")
                                    .font(.system(size: 12)).foregroundStyle(muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }.padding(24)
        }
    }
}

struct AnswerView: View {
    let text: String
    let sources: [Hit]
    @ObservedObject var model: BrainModel
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let attributed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                Text(attributed).textSelection(.enabled)
            } else {
                Text(text).textSelection(.enabled)
            }
            if !sources.isEmpty {
                SmallLabel(text: "Belägg").padding(.top, 4)
                ForEach(Array(sources.enumerated()), id: \.element.id) { index, source in
                    Button {
                        model.show(.search)
                        model.select(source)
                    } label: {
                        HStack(spacing: 6) {
                            Text("[\(index + 1)]").foregroundStyle(lime).font(.system(.caption, design: .monospaced))
                            Text(source.title).lineLimit(1)
                            Spacer()
                            Image(systemName: "arrow.up.right").font(.system(size: 9)).foregroundStyle(ice)
                        }
                    }.buttonStyle(.plain).accessibilityLabel("Källa \(index + 1), \(source.title)")
                }
            }
        }.font(.system(size: 12)).lineSpacing(3)
    }
}

struct QueryBox: View {
    static let prominentFont = Font.system(size: 16)
    static let prominentRadius: CGFloat = 18
    static let focusBorder = Color.accentColor.opacity(0.85)

    @FocusState private var fieldFocused: Bool
    @Binding var query: String
    let placeholder: String
    var autofocus = true
    var prominent = false
    var focus: FocusState<Bool>.Binding?
    var attachedResults = false
    var action: () -> Void
    private var searchFocus: FocusState<Bool>.Binding { focus ?? $fieldFocused }

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass").foregroundStyle(ice)
            TextField(placeholder, text: $query).textFieldStyle(.plain).onSubmit(action)
                .accessibilityLabel(placeholder).focused(searchFocus)
                .onAppear { if autofocus { searchFocus.wrappedValue = true } }
            if !query.isEmpty {
                Button { query = ""; action() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(muted)
                }.buttonStyle(.plain).accessibilityLabel("Rensa sökningen")
            }
        }
        .font(prominent ? Self.prominentFont : .body)
        .padding(.horizontal, prominent ? 17 : 12)
        .padding(.vertical, prominent ? 15 : 10)
        .background(inset.opacity(prominent ? 0.55 : 1), in: outline)
        .background {
            if prominent { outline.fill(.clear).brainGlass(outline, tint: .indigo.opacity(0.16)) }
        }
        .overlay {
            outline.strokeBorder(attachedResults || searchFocus.wrappedValue ? Self.focusBorder : .white.opacity(0.18))
                .mask { Rectangle().padding(.bottom, attachedResults ? 1 : 0) }
                .allowsHitTesting(false)
        }
    }

    private var outline: UnevenRoundedRectangle {
        let radius = prominent ? Self.prominentRadius : 10
        let lowerRadius = attachedResults ? 0 : radius
        return UnevenRoundedRectangle(topLeadingRadius: radius, bottomLeadingRadius: lowerRadius,
                                     bottomTrailingRadius: lowerRadius, topTrailingRadius: radius)
    }
}

struct HitCell: View {
    let hit: Hit
    let active: Bool
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: hit.kind == "skill" ? "square.stack.3d.up" : hit.kind == "inbox" ? "tray" : "doc.text")
                .foregroundStyle(active ? lime : ice).font(.system(size: 12)).frame(width: 15).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(hit.title).font(.system(size: 13, weight: .medium)).lineLimit(2)
                if hit.excerpt.isEmpty {
                    Text(hit.path).lineLimit(1)
                } else {
                    Text(hit.excerpt.replacingOccurrences(of: "\n", with: " ")).lineLimit(2)
                }
            }.foregroundStyle(muted).font(.system(size: 11))
            Spacer(minLength: 0)
            if hit.match != "text" { Badge(text: hit.match == "hybrid" ? "HYBRID" : "VEKTOR", tint: lime) }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(active ? lime.opacity(0.08) : panel, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(active ? lime.opacity(0.28) : line))
        .contentShape(Rectangle())
    }
}

struct LibraryView: View {
    @ObservedObject var model: BrainModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var searchFocused: Bool
    @LocalState private var showPinned = false

    private var isLibrary: Bool { model.section == .search }
    private var browsing: Bool { model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var filteringPins: Bool { showPinned && browsing }
    private var visibleHits: [Hit] {
        isLibrary && filteringPins ? model.hits.filter { model.pinnedNotes.contains($0.id) } : model.hits
    }

    var body: some View {
        Group {
            if isLibrary {
                VStack(alignment: .leading, spacing: 11) {
                    HStack(alignment: .firstTextBaseline) {
                        WorkspaceTitle("Bibliotek")
                        Spacer()
                        if !Distribution.store { agentTools }
                    }
                    HSplitView {
                        VStack(spacing: 10) {
                            searchField(prominent: true)
                            if browsing || model.searching {
                                HStack {
                                    if browsing {
                                        ActionButton(title: showPinned ? "Fästa" : "Alla anteckningar",
                                                     icon: showPinned ? "pin.fill" : "pin", primary: showPinned) {
                                            withAnimation(reduceMotion ? nil : .smooth(duration: 0.22)) { showPinned.toggle() }
                                            BrainHaptics.selection()
                                        }
                                        .help(showPinned ? "Visa alla anteckningar" : "Visa bara fästa anteckningar")
                                        .accessibilityIdentifier("library-pinned-filter")
                                    }
                                    Spacer()
                                    if model.searching { ProgressView().controlSize(.small) }
                                }
                            }
                            results
                        }
                        .padding(.trailing, 14)
                        .frame(minWidth: 255, idealWidth: 303)
                        detail
                            .padding(.leading, 14)
                            .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
                            .layoutPriority(1)
                    }
                }
                .padding(.top, 14)
            } else {
                VStack(alignment: .leading, spacing: 13) {
                    if model.section == .inbox {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                SmallLabel(text: "Råmaterial", tint: lime)
                                Text("Källor på väg in").font(.system(size: 24, weight: .medium, design: .serif))
                            }
                            Spacer()
                            ActionButton(title: "Uppdatera", icon: "arrow.clockwise") { Task { await model.search() } }
                        }
                    } else {
                        searchField(prominent: false)
                    }
                    HStack(alignment: .top, spacing: 13) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                SmallLabel(text: model.section == .skills ? "Metoder" : "Inkorg")
                                Spacer()
                                if model.searching { ProgressView().controlSize(.small) }
                            }
                            results
                        }
                        .frame(width: 285)
                        ScrollView { detail }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 21)
        .padding(.bottom, 19)
    }

    private func searchField(prominent: Bool) -> some View {
        QueryBox(query: $model.query,
                 placeholder: prominent ? "Sök i biblioteket…" : "Sök efter en återanvändbar metod…",
                 prominent: prominent, focus: $searchFocused) {
            Task { await model.search() }
        }
        .task(id: model.query) {
            do { try await Task.sleep(for: .milliseconds(280)); await model.search() } catch {}
        }
        .onChange(of: model.librarySearchRequest) { _, _ in
            if prominent { searchFocused = true }
        }
        .accessibilityIdentifier(prominent ? "library-search" : "skills-search")
    }

    private var agentTools: some View {
        NoteActionBar {
            Menu {
                Button("Kopiera källpaket", systemImage: "square.on.square", action: model.copyContext)
                Button("Backtest", systemImage: "chart.xyaxis.line") {
                    Task { _ = await model.run("audit", query: model.query) }
                }
                Button("Motläs", systemImage: "arrow.left.arrow.right") {
                    Task { _ = await model.run("challenge", query: model.query) }
                }
                Button("Idélabb", systemImage: "point.3.connected.trianglepath.dotted") {
                    Task { _ = await model.run("explore", query: model.query) }
                }
            } label: {
                Label("Sökverktyg", systemImage: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .padding(.horizontal, 10).padding(.vertical, 7)
            .brainGlass(Capsule(), interactive: true)
            ActionButton(title: model.running ? "Arbetar…" : "Fråga", icon: "sparkle", primary: true) {
                Task { _ = await model.run("ask", query: model.query) }
            }
        }
        .disabled(browsing || model.running)
    }

    private var results: some View {
        ScrollView {
            LazyVStack(spacing: isLibrary ? 2 : 6) {
                if visibleHits.isEmpty && !model.searching { listEmptyState }
                ForEach(visibleHits) { hit in
                    let selected = model.selected?.id == hit.id
                    Button {
                        if model.selected?.id != hit.id { BrainHaptics.selection() }
                        model.select(hit)
                    } label: {
                        if isLibrary {
                            LibraryRow(hit: hit, selected: selected, pinned: model.pinnedNotes.contains(hit.id),
                                       appearance: model.appearance(for: hit))
                        } else {
                            HitCell(hit: hit, active: selected)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("library-note-" + hit.id)
                }
            }
        }
        .defaultScrollAnchor(.top)
        .scrollBounceBehavior(.basedOnSize)
    }

    @ViewBuilder
    private var listEmptyState: some View {
        if isLibrary {
            ContentUnavailableView(
                !browsing ? "Inga sökträffar" : filteringPins ? "Inga fästa anteckningar" : "Biblioteket är tomt",
                systemImage: filteringPins ? "pin.slash" : browsing ? "books.vertical" : "magnifyingglass",
                description: Text(!browsing ? "Prova ett annat sökord." : filteringPins
                                  ? "Fäst en anteckning från dess detaljvy."
                                  : "Skapa eller importera en anteckning för att börja."))
        } else {
            EmptyPanel(icon: model.section.icon, title: model.section == .inbox ? "Inkorgen är tom" : "Inga träffar",
                       detail: model.section == .inbox ? "Lägg till en källa för att börja." : "Prova ett mer specifikt ord eller ämne.")
        }
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let reply = model.reply, let answer = reply.answer, model.section != .skills {
                if isLibrary && model.selected != nil {
                    ScrollView { replyCard(reply, answer: answer) }.frame(maxHeight: 176)
                } else {
                    replyCard(reply, answer: answer)
                }
            }
            if let hit = model.selected {
                NoteView(model: model, hit: hit, libraryPresentation: isLibrary)
                    .id(hit.id)
                    .transition(.opacity)
            } else if model.reply == nil || model.section == .skills {
                if isLibrary {
                    ContentUnavailableView("Välj en anteckning", systemImage: "doc.text",
                                           description: Text("Öppna en anteckning för att läsa eller fortsätta skriva."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity)
                } else {
                    EmptyPanel(icon: "doc.text.magnifyingglass", title: "Öppna en träff",
                               detail: model.section == .skills ? "Här visas metoden du väljer." : "Välj en anteckning för att läsa eller skriva vidare.")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(isLibrary && !reduceMotion ? .easeInOut(duration: 0.18) : nil, value: model.selected?.id)
    }

    private func replyCard(_ reply: AgentReply, answer: String) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    SmallLabel(text: "Agentens läsning", tint: lime)
                    Spacer()
                    ActionButton(title: "Kopiera", icon: "square.on.square") { model.copy(answer) }
                    Button { model.reply = nil } label: { Image(systemName: "xmark").font(.system(size: 11)) }
                        .buttonStyle(.plain).accessibilityLabel("Stäng agentsvaret")
                }
                AnswerView(text: answer, sources: reply.sources ?? [], model: model)
                if reply.proposal != nil {
                    ActionButton(title: "Granska förslaget", icon: "arrow.right") { model.show(.review) }
                }
            }
        }
    }
}

private struct LibraryRow: View {
    let hit: Hit
    let selected: Bool
    let pinned: Bool
    let appearance: NoteAppearance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @LocalState private var hovering = false

    var body: some View {
        let tint = appearance.accent.tint
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: appearance.symbol == .document && hit.kind == "skill" ? "square.stack.3d.up" : appearance.symbol.icon)
                .font(.system(size: 15, weight: .medium)).foregroundStyle(tint)
                .frame(width: 29, height: 29)
                .background(tint.opacity(selected ? 0.19 : 0.11), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(hit.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                let preview = (hit.preview ?? hit.excerpt).replacingOccurrences(of: "\n", with: " ")
                if !preview.isEmpty {
                    Text(preview).font(.system(size: 12)).foregroundStyle(muted).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if pinned {
                Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(tint)
                    .accessibilityLabel("Fäst anteckning")
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 9)
        .background(tint.opacity(selected ? 0.13 : hovering ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 11))
        .overlay(alignment: .leading) {
            if selected {
                Capsule().fill(tint).frame(width: 2, height: 19).padding(.leading, 2).allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: selected)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hovering)
    }
}

struct NoteView: View {
    @ObservedObject var model: BrainModel
    let hit: Hit
    var libraryPresentation = false
    @StateObject private var reader = StudioEditorControl()
    @LocalState private var related: [Hit]?
    @LocalState private var relatedRevision: String?
    @LocalState private var linking = false
    @LocalState private var raw = false

    private var currentNote: Note? { model.note.flatMap { $0.path == hit.path ? $0 : nil } }
    private var editable: Bool { hit.kind == "note" && !hit.path.hasPrefix("Codex Skills/") }
    private var pinned: Bool { model.pinnedNotes.contains(hit.id) }

    var body: some View {
        if libraryPresentation { readerPanel } else { legacyPanel }
    }

    private var readerPanel: some View {
        let appearance = model.appearance(for: hit)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: appearance.symbol.icon)
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(appearance.accent.tint)
                    .frame(width: 30, height: 30)
                    .background(appearance.accent.tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 9))
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
                NoteActionBar {
                    if hit.kind != "skill" {
                        ActionButton(title: "Visa fil", icon: "arrow.up.right") { model.reveal(hit.path) }
                    }
                    ActionButton(title: "Kopiera", icon: "square.on.square") {
                        guard let note = currentNote else { return }
                        model.copy(note.body)
                        BrainHaptics.action()
                    }
                    .disabled(currentNote == nil)
                    if editable {
                        ActionButton(title: "Redigera", icon: "square.and.pencil", primary: true) {
                            BrainHaptics.action()
                            model.openEditor(for: hit)
                        }
                        .disabled(currentNote == nil)
                        .accessibilityIdentifier("library-edit-note")
                    }
                    readerMenu
                }
            }
            Divider().overlay(appearance.accent.tint.opacity(0.12))
            if let note = currentNote {
                if !note.body.split(separator: "\n", maxSplits: 40).contains(where: { $0.hasPrefix("# ") }) {
                    Text(hit.title).font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader).textSelection(.enabled)
                        .padding(.horizontal, 12)
                }
                StudioTextEditor(markdown: note.body, raw: raw, busy: true, control: reader, onChange: { _ in },
                                 openCitation: { model.openEditor(for: hit, citation: $0) })
                    .id(raw)
                    .accessibilityIdentifier("library-note-reader")
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let related, let note = currentNote, relatedRevision == note.revision {
                ScrollView { relatedResults(related, note: note) }.frame(maxHeight: 160)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 3)
    }

    private var readerMenu: some View {
        Menu {
            Button("Sök i anteckningen", systemImage: "magnifyingglass") {
                reader.view?.showFindInterface(.showFindInterface)
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(currentNote == nil)
            Button(raw ? "Visa formaterat" : "Visa Markdown", systemImage: "chevron.left.forwardslash.chevron.right") {
                raw.toggle()
            }
            .disabled(currentNote == nil)
            if hit.kind == "note" {
                Divider()
                Button(pinned ? "Lossa anteckningen" : "Fäst anteckningen", systemImage: pinned ? "pin.slash" : "pin") {
                    model.togglePin(hit)
                }
                Picker("Färg", selection: appearanceBinding(\.accent)) {
                    ForEach(NoteAppearance.Accent.allCases, id: \.self) { accent in
                        Label(accent.rawValue, systemImage: "circle.fill").tag(accent)
                    }
                }
                Picker("Symbol", selection: appearanceBinding(\.symbol)) {
                    ForEach(NoteAppearance.Symbol.allCases, id: \.self) { symbol in
                        Label(symbol.rawValue, systemImage: symbol.icon).tag(symbol)
                    }
                }
            }
            if hit.kind == "inbox" {
                Button("Analysera källan", systemImage: "sparkle") {
                    Task { _ = await model.run("ingest", path: hit.path) }
                }.disabled(model.running)
            } else if editable, let note = currentNote {
                Button("Sök relaterat", systemImage: "link") { findRelated(to: note) }.disabled(linking)
            }
        } label: {
            Image(systemName: "ellipsis").frame(width: 17, height: 14)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.horizontal, 8).padding(.vertical, 7)
        .brainGlass(Capsule(), interactive: true)
        .accessibilityLabel("Fler anteckningsåtgärder")
        .accessibilityIdentifier("library-note-actions")
    }

    private func appearanceBinding<Value>(_ keyPath: WritableKeyPath<NoteAppearance, Value>) -> Binding<Value> {
        Binding(get: { model.appearance(for: hit)[keyPath: keyPath] }, set: { value in
            var appearance = model.appearance(for: hit)
            appearance[keyPath: keyPath] = value
            model.setAppearance(appearance, for: hit)
        })
    }

    private func findRelated(to note: Note) {
        linking = true
        Task {
            defer { linking = false }
            do {
                related = try await Bridge.invoke(["related", "--", note.path])
                relatedRevision = note.revision
            } catch {
                model.error = error.localizedDescription
            }
        }
    }

    private func relatedResults(_ related: [Hit], note: Note) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            SmallLabel(text: "Relaterade sökträffar", tint: lime)
            if related.isEmpty {
                Text("Inga andra anteckningar matchade sökningen.").foregroundStyle(muted)
            }
            ForEach(related) { candidate in
                VStack(alignment: .leading, spacing: 6) {
                    Button(candidate.title) { model.select(candidate, train: false) }.buttonStyle(.plain)
                    Text(candidate.excerpt).font(.system(size: 12)).foregroundStyle(muted).textSelection(.enabled)
                    ActionButton(title: "Granska länkförslag", icon: "arrow.right") {
                        linking = true
                        Task {
                            defer { linking = false }
                            await model.stageLink(from: note, to: candidate)
                        }
                    }.disabled(linking)
                        .accessibilityLabel("Granska länkförslag till \(candidate.title)")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var legacyPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                SmallLabel(text: hit.kind == "skill" ? "Skill / instruktion" : "Bibliotek / Markdown", tint: lime)
                Text(hit.title).font(.system(size: 22, weight: .medium, design: .serif)).textSelection(.enabled)
                Text(hit.path).font(.system(size: 10, design: .monospaced)).foregroundStyle(muted).textSelection(.enabled)
                HStack(spacing: 7) {
                    if hit.kind != "skill" {
                        ActionButton(title: "Visa fil", icon: "arrow.up.right") { model.reveal(hit.path) }
                    }
                    if hit.kind == "inbox" {
                        ActionButton(title: model.running ? "Läser…" : "Analysera källan", icon: "sparkle", primary: true) {
                            Task { _ = await model.run("ingest", path: hit.path) }
                        }.disabled(model.running)
                    } else if hit.kind == "note", !hit.path.hasPrefix("Codex Skills/"), let note = model.note, note.path == hit.path {
                        ActionButton(title: "Redigera", icon: "pencil") { model.openEditor(for: hit) }
                        ActionButton(title: "Sök relaterat", icon: "link") {
                            findRelated(to: note)
                        }.disabled(linking)
                    }
                    if let note = model.note {
                        ActionButton(title: "Kopiera", icon: "square.on.square") { model.copy(note.body) }
                    }
                }
                if let related, let note = model.note, relatedRevision == note.revision {
                    relatedResults(related, note: note)
                }
                Divider()
                if let note = model.note {
                    Text(note.body.isEmpty ? "Tom anteckning" : note.body)
                        .font(.system(size: 12, design: .monospaced)).lineSpacing(4)
                        .foregroundStyle(.white.opacity(0.87)).textSelection(.enabled)
                } else { ProgressView().controlSize(.small) }
            }
        }
    }
}

struct ReviewView: View {
    @ObservedObject var model: BrainModel

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            VStack(alignment: .leading, spacing: 9) {
                SmallLabel(text: "Granskningskö", tint: lime)
                ScrollView {
                    VStack(spacing: 7) {
                        if (model.dashboard?.proposals ?? []).isEmpty {
                            EmptyPanel(icon: "rectangle.split.2x1", title: "Inga ändringsförslag", detail: "Förslag från agenten och dina egna ändringar visas här.")
                        }
                        ForEach(model.dashboard?.proposals ?? []) { change in
                            Button { model.openChange(change) } label: {
                                Panel {
                                    VStack(alignment: .leading, spacing: 7) {
                                        Badge(text: change.status == "pending" ? "ATT GRANSKA" : change.status == "accepted" ? "GODKÄND" : "AVVISAD",
                                              tint: change.status == "pending" ? lime : ice)
                                        Text(change.path).font(.system(size: 12, weight: .medium)).lineLimit(2)
                                        Text(change.reason).foregroundStyle(muted).font(.system(size: 11)).lineLimit(2)
                                    }
                                }.overlay(RoundedRectangle(cornerRadius: 12).stroke(model.selectedChange?.id == change.id ? lime.opacity(0.4) : .clear))
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }.frame(width: 270)
            ScrollView {
                if let change = model.selectedChange, let detail = model.detail {
                    Panel {
                        VStack(alignment: .leading, spacing: 12) {
                            SmallLabel(text: "Före / efter", tint: lime)
                            Text(change.path).font(.system(size: 20, weight: .medium, design: .serif)).textSelection(.enabled)
                            Text(change.reason).foregroundStyle(muted).font(.system(size: 12)).textSelection(.enabled)
                            if !change.source.isEmpty {
                                ActionButton(title: "Visa källfilen", icon: "arrow.up.right") { model.reveal(change.source) }
                            }
                            if detail.conflict {
                                Text(detail.linkConflict == true
                                     ? "Källanteckningen har ändrats, flyttats eller tagits bort. Skapa ett nytt länkförslag."
                                     : "Anteckningen har ändrats sedan förslaget skapades. Läs den aktuella versionen och skapa ett nytt förslag.")
                                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.orange)
                            }
                            if detail.status == "pending" {
                                HStack(spacing: 8) {
                                    ActionButton(title: "Godkänn och skriv", icon: "checkmark", primary: true) { model.decide(change, accept: true) }
                                        .disabled(detail.conflict)
                                    ActionButton(title: "Avvisa", icon: "xmark") { model.decide(change, accept: false) }
                                }.disabled(model.decidingChangeID != nil)
                            }
                            if detail.diff.isEmpty {
                                Text("Förslaget motsvarar anteckningens aktuella innehåll.").font(.system(size: 12)).foregroundStyle(muted)
                            } else {
                                ScrollView(.horizontal) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        ForEach(Array(detail.diff.split(separator: "\n", omittingEmptySubsequences: false).enumerated()), id: \.offset) { _, row in
                                            Text(String(row)).font(.system(size: 11, design: .monospaced))
                                                .foregroundStyle(row.hasPrefix("+") ? lime : row.hasPrefix("-") ? Color.pink.opacity(0.86) : muted)
                                        }
                                    }.textSelection(.enabled)
                                }.padding(10).background(inset, in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                } else {
                    EmptyPanel(icon: "rectangle.split.2x1", title: "Välj ett förslag", detail: "Se exakt vilka rader som tillkommer eller tas bort.")
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.padding(21)
    }
}

struct EditorField: View {
    let title: String
    @Binding var text: String
    var height: CGFloat = 100
    var autofocus = false
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SmallLabel(text: title)
            TextEditor(text: $text).font(.system(size: 13)).scrollContentBackground(.hidden)
                .padding(7).frame(height: height)
                .background(inset, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(line))
                .accessibilityLabel(title)
                .focused($focused)
        }
        .onAppear { if autofocus { focused = true } }
    }
}

struct WritingView: View {
    @ObservedObject var model: BrainModel
    @LocalState private var brief = ""
    @LocalState private var before = ""
    @LocalState private var after = ""
    @LocalState private var rule = ""
    @LocalState private var genre = ""
    @LocalState private var comparison = ""
    @LocalState private var learning = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        SmallLabel(text: "Stilateljé  /  Redaktionsminne", tint: lime)
                        Text("Formell prosa, med egen rytm").font(.system(size: 28, weight: .medium, design: .serif))
                    }
                    Spacer()
                    Picker("Språk", selection: $model.language) {
                        Text("Svenska").tag("sv")
                        Text("English").tag("en")
                    }.pickerStyle(.segmented).frame(width: 174).disabled(model.running || learning)
                }
                Panel {
                    VStack(alignment: .leading, spacing: 10) {
                        EditorField(title: "Vad ska texten göra?", text: $brief, height: 78)
                        HStack {
                            ActionButton(title: model.running ? "Arbetar…" : "Skriv utkast", icon: "pencil.line", primary: true) {
                                Task {
                                    if let result = await model.run("write", query: brief), let answer = result.answer {
                                        before = answer
                                        after = answer
                                        rule = ""
                                        comparison = ""
                                    }
                                }
                            }.disabled(model.running || brief.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            if !before.isEmpty {
                                ActionButton(title: "Kopiera utkast", icon: "square.on.square") { model.copy(before) }
                            }
                        }
                    }
                }
                Panel {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            SmallLabel(text: "Lär av en godkänd redigering", tint: lime)
                            Spacer()
                            Badge(text: model.language.uppercased())
                        }
                        HStack(alignment: .top, spacing: 10) {
                            EditorField(title: "Före", text: $before, height: 110)
                            EditorField(title: "Godkänd version", text: $after, height: 110)
                        }
                        TextField("Genre eller sammanhang, t.ex. forskningsrapport", text: $genre).textFieldStyle(.roundedBorder)
                        TextField("Redaktionsregel för framtida texter", text: $rule, axis: .vertical)
                            .textFieldStyle(.roundedBorder).lineLimit(1...3)
                        if !comparison.isEmpty {
                            Text(comparison).font(.system(size: 12)).foregroundStyle(muted).textSelection(.enabled)
                        }
                        HStack {
                            ActionButton(title: "Föreslå en regel", icon: "sparkle") {
                                Task {
                                    if let result = await model.run("learn", before: before, after: after, genre: genre) {
                                        rule = result.rule ?? ""
                                        comparison = result.answer ?? ""
                                    }
                                }
                            }.disabled(model.running || before.isEmpty || after.isEmpty || before == after)
                            ActionButton(title: "Godkänn och lär", icon: "checkmark", primary: true) {
                                Task {
                                    guard !learning else { return }
                                    learning = true
                                    defer { learning = false }
                                    if await model.learn(before: before, after: after, genre: genre, rule: rule) {
                                        before = ""; after = ""; rule = ""; comparison = ""
                                    }
                                }
                            }.disabled(learning || before.isEmpty || after.isEmpty || before == after || rule.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
                if let profile = model.profile, profile.language == model.language {
                    Panel {
                        VStack(alignment: .leading, spacing: 9) {
                            HStack {
                                SmallLabel(text: "Profilens regler")
                                Spacer()
                                Badge(text: "\(profile.examples.count) LÄRDA")
                            }
                            ForEach(profile.defaults, id: \.self) { value in
                                Text(value).font(.system(size: 12)).foregroundStyle(muted)
                            }
                            ForEach(profile.examples) { item in
                                Divider()
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(item.rule).font(.system(size: 12, weight: .medium)).textSelection(.enabled)
                                        if !item.genre.isEmpty { Text(item.genre).font(.system(size: 10)).foregroundStyle(muted) }
                                    }
                                    Spacer()
                                    Button { model.forget(item) } label: { Image(systemName: "trash").foregroundStyle(muted) }
                                        .buttonStyle(.plain).accessibilityLabel("Ta bort regeln")
                                }
                            }
                        }
                    }
                }
            }.padding(21)
        }
        .task(id: model.language) { await model.loadStyle() }
        .onChange(of: model.language) { _, _ in
            before = ""; after = ""; rule = ""; genre = ""; comparison = ""
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: BrainModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Panel {
                    VStack(alignment: .leading, spacing: 9) {
                        SmallLabel(text: "Valv och modell", tint: lime)
                        TextField("Bibliotekets mapp", text: $model.vaultInput).textFieldStyle(.roundedBorder)
                    if model.dashboard?.config.native == true {
                        Badge(text: "EGET BIGBRAIN-BIBLIOTEK", tint: lime)
                    }
                        TextField("Codex CLI", text: $model.codexInput).textFieldStyle(.roundedBorder)
                        TextField("QMD, valfri sökväg", text: $model.qmdInput).textFieldStyle(.roundedBorder)
                        HStack {
                            ActionButton(title: "Importera Markdown", icon: "square.and.arrow.down") {
                                let panel = NSOpenPanel()
                                panel.canChooseFiles = false
                                panel.canChooseDirectories = true
                                panel.allowsMultipleSelection = false
                                if panel.runModal() == .OK, let url = panel.url { model.adopt(url) }
                            }
                            ActionButton(title: "Importera Word", icon: "doc.badge.plus") {
                                let panel = NSOpenPanel()
                                panel.canChooseFiles = true
                                panel.canChooseDirectories = false
                                panel.allowsMultipleSelection = false
                                if let word = UTType(filenameExtension: "docx") {
                                    panel.allowedContentTypes = [word]
                                }
                                panel.message = "Importerar text, rubriker, listor, webblänkar och enkla tabeller lokalt. Bilder, kommentarer och spårningshistorik utelämnas."
                                if panel.runModal() == .OK, let url = panel.url { model.importWord(url) }
                            }
                            .disabled(model.importing)
                            ActionButton(title: "Spara inställningar", icon: "checkmark", primary: true) { model.saveSettings() }
                        }
                        Text(Distribution.store
                             ? "Anteckningar, index och skrivprofiler lagras i appens lokala bibliotek. Agentsvar körs med Apple Intelligence på enheten."
                             : "Index och skrivprofiler lagras lokalt. När du använder Codex får det frågan och de utdrag som valts för jobbet.")
                            .font(.system(size: 12)).foregroundStyle(muted)
                    }
                }
                if !Distribution.store {
                    Panel {
                        VStack(alignment: .leading, spacing: 10) {
                            SmallLabel(text: "Nya Codex-chattar", tint: lime)
                        Text("Länka dina nya chattar till samma bibliotek och de godkända skrivprofilerna.")
                            .font(.system(size: 12)).foregroundStyle(muted)
                            ActionButton(title: "Anslut skills till Codex", icon: "link") { model.install() }
                        }
                    }
                }
                Panel {
                    VStack(alignment: .leading, spacing: 10) {
                        SmallLabel(text: "Bakgrund och sökindex", tint: lime)
                        if !Distribution.store {
                            Toggle("Automatisk källradar medan appen körs", isOn: $model.auto)
                                .toggleStyle(.switch).tint(lime)
                        }
                        Toggle("Lär samband när jag öppnar noder", isOn: $model.learningEnabled)
                            .toggleStyle(.switch).tint(lime)
                        Text("Spara för att använda inställningarna. Inlärda kopplingar lagras lokalt.")
                            .font(.system(size: 12)).foregroundStyle(muted)
                        HStack {
                            Badge(text: model.dashboard?.vectors == true ? "QMD REDO" : "TEXTINDEX REDO",
                                  tint: model.dashboard?.vectors == true ? lime : ice)
                            if !Distribution.store {
                                ActionButton(title: model.vectorBusy ? "Bygger vektorindex…" : "Bygg om vektorindex", icon: "point.3.connected.trianglepath.dotted") { model.vectors() }
                                    .disabled(model.vectorBusy || model.dashboard?.vectorAvailable != true)
                            }
                            ActionButton(title: "Uppdatera textindex", icon: "arrow.clockwise") { Task { await model.refresh(force: true) } }
                        }
                    }
                }
            }.padding(21)
        }
    }
}

@available(macOS 26.0, *)
struct TranscriptionView: View {
    @ObservedObject var model: BrainModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var session = TranscriptionSession()
    @LocalState private var title = ""
    @LocalState private var language = "sv-SE"
    @LocalState private var saving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Transkribera ljud").font(.system(size: 25, weight: .semibold))
            Text("Ljudet bearbetas på din Mac. Vid första användningen kan en språkmodell behöva hämtas från Apple.")
                .font(.system(size: 12)).foregroundStyle(muted)
            Picker("Språk i ljudet", selection: $language) {
                Text("Svenska").tag("sv-SE")
                Text("Engelska").tag("en-US")
            }.disabled(session.recording || session.working || saving)
            HStack {
                if session.recording {
                    ActionButton(title: "Stoppa och transkribera", icon: "stop.circle", primary: true) {
                        session.stopRecording()
                    }
                } else {
                    ActionButton(title: "Spela in", icon: "mic") {
                        if title.isEmpty { title = "Röstanteckning" }
                        session.startRecording(locale: Locale(identifier: language))
                    }.disabled(session.working || saving)
                    ActionButton(title: "Välj ljudfil", icon: "doc.badge.plus") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = false
                        panel.allowsMultipleSelection = false
                        panel.allowedContentTypes = [.audio]
                        if panel.runModal() == .OK, let url = panel.url {
                            if title.isEmpty { title = url.deletingPathExtension().lastPathComponent }
                            session.transcribe(url, locale: Locale(identifier: language))
                        }
                    }.disabled(session.working || saving)
                }
                if session.working {
                    ProgressView().controlSize(.small)
                    ActionButton(title: "Avbryt bearbetning") { session.cancel() }
                }
                if !session.status.isEmpty { Text(session.status).foregroundStyle(muted) }
            }
            if let error = session.error {
                Text(error).font(.system(size: 12)).foregroundStyle(.orange).textSelection(.enabled)
            }
            TextField("Rubrik", text: $title).textFieldStyle(.roundedBorder).disabled(saving)
            EditorField(title: "Transkriberad text", text: $session.draft, height: 250).disabled(saving)
            HStack {
                Spacer()
                ActionButton(title: "Stäng") { dismiss() }.keyboardShortcut(.cancelAction).disabled(saving)
                ActionButton(title: saving ? "Sparar…" : "Spara anteckning", icon: "checkmark", primary: true) {
                    saving = true
                    Task {
                        defer { saving = false }
                        if await model.capture(title: title, body: session.draft, source: "", inbox: false) { dismiss() }
                    }
                }.disabled(saving || session.recording || session.working ||
                           title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                           session.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24).frame(width: 615).background(base)
        .interactiveDismissDisabled(saving)
        .onDisappear { session.cancel() }
    }
}

struct CaptureView: View {
    @ObservedObject var model: BrainModel
    @Environment(\.dismiss) var dismiss
    @LocalState private var title = ""
    @LocalState private var source = ""
    @LocalState private var text = ""
    @LocalState private var saving = false
    @LocalState private var extracting = false
    @LocalState private var inbox = !Distribution.store
    @LocalState private var optionsExpanded = false
    @LocalState private var template: NoteTemplate?

    private var captureTitle: String {
        let explicitTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicitTitle.isEmpty { return explicitTitle }
        let firstLine = text.split(whereSeparator: \.isNewline)
            .lazy.map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        return firstLine.map { String($0.prefix(72)) } ?? "Ny anteckning"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("Fånga snabbt").font(.system(size: 25, weight: .semibold))
                Spacer()
                Menu("Mallar") {
                    ForEach(NoteTemplate.allCases, id: \.self) { template in
                        Button(template.rawValue, systemImage: template.appearance.symbol.icon) {
                            apply(template)
                        }
                    }
                }
                .fixedSize().disabled(saving)
            }
            EditorField(title: "Anteckning", text: $text, height: 175, autofocus: true)
                .disabled(saving)
            DisclosureGroup("Rubrik, källa och plats", isExpanded: $optionsExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Rubrik, valfri", text: $title).textFieldStyle(.roundedBorder)
                    HStack {
                        TextField("Källänk, valfri", text: $source).textFieldStyle(.roundedBorder)
                        if !Distribution.store {
                            ActionButton(title: extracting ? "Hämtar…" : "Hämta artikel", icon: "arrow.down.doc") {
                                extracting = true
                                Task {
                                    defer { extracting = false }
                                    if let result = await model.extract(source) {
                                        text = text.isEmpty ? result : text + "\n\n" + result
                                    }
                                }
                            }.disabled(extracting || source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    Picker("Spara som", selection: $inbox) {
                        Text("Anteckning").tag(false)
                        Text("Källa i inkorgen").tag(true)
                    }.pickerStyle(.segmented)
                }
                .padding(.top, 6)
            }.disabled(saving)
            HStack {
                Text(inbox ? "Sparas i inkorgen" : "Sparas i biblioteket och visas i Atlas")
                    .font(.system(size: 12)).foregroundStyle(muted)
                Spacer()
                ActionButton(title: "Avbryt") { dismiss() }.keyboardShortcut(.cancelAction).disabled(saving)
                ActionButton(title: saving ? "Sparar…" : "Spara", icon: "checkmark", primary: true) {
                    saving = true
                    Task {
                        defer { saving = false }
                        if await model.capture(title: captureTitle, body: text, source: source, inbox: inbox,
                                               appearance: template?.appearance) { dismiss() }
                    }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(saving || extracting || (text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                                                   source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }
        }
        .padding(24).frame(width: 510).background(base)
        .interactiveDismissDisabled(saving)
    }

    private func apply(_ template: NoteTemplate) {
        self.template = template
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { title = template.rawValue }
        let existing = text.trimmingCharacters(in: .whitespacesAndNewlines)
        text = existing.isEmpty ? template.body : existing + "\n\n" + template.body
        inbox = false
        optionsExpanded = true
        BrainHaptics.selection()
    }
}

private enum NoteTemplate: String, CaseIterable {
    case meeting = "Mötesanteckning", study = "Studieanteckning", tasks = "Uppgiftslista"

    var body: String {
        switch self {
        case .meeting: "## Agenda\n\n## Beslut\n\n## Nästa steg\n\n- [ ] Lägg till ansvarig och datum"
        case .study: "## Fråga\n\n## Viktiga begrepp\n\n## Förklaring med egna ord\n\n## Repetition"
        case .tasks: "## Att göra\n\n- [ ] Lägg till första uppgiften\n\n## Uppföljning"
        }
    }

    var appearance: NoteAppearance {
        switch self {
        case .meeting: NoteAppearance(accent: .lavender, symbol: .meeting)
        case .study: NoteAppearance(accent: .ocean, symbol: .study)
        case .tasks: NoteAppearance(accent: .mint, symbol: .tasks)
        }
    }
}

struct RootView: View {
    @ObservedObject var model: BrainModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var workspace: some View {
        HStack(spacing: 0) {
            Sidebar(model: model)
            VStack(spacing: 0) {
                Header(model: model)
                switch model.section {
                case .atlas: AtlasView(model: model)
                case .radar: RadarView(model: model)
                case .search, .skills, .inbox: LibraryView(model: model)
                case .review: ReviewView(model: model)
                case .writing: WritingView(model: model)
                case .settings: SettingsView(model: model)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    var body: some View {
        NavigationStack {
            workspace
                .navigationDestination(item: Binding(get: { model.editorHit }, set: {
                    if $0 == nil { model.closeEditor() }
                })) { hit in
                    if let note = model.note, note.path == hit.path {
                        StudioNoteView(model: model, hit: hit, note: note, citation: model.editorCitation)
                            .id(note.file)
                            .navigationBarBackButtonHidden()
                    }
                }
        }
        .frame(minWidth: 975, minHeight: 655)
        .foregroundStyle(.white)
        .background {
            ZStack {
                base
                RadialGradient(colors: [Color.indigo.opacity(0.38), .clear], center: .topLeading, startRadius: 0, endRadius: 615)
                RadialGradient(colors: [Color.blue.opacity(0.29), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 520)
            }.ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
        .environment(\.openURL, OpenURLAction { url in
            guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return .discarded }
            return .systemAction
        })
        .overlay(alignment: .bottomTrailing) {
            if !model.toast.isEmpty {
                Label(model.toast, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(lime).padding(11)
                    .brainGlass(Capsule(), tint: .teal.opacity(0.18))
                    .padding(18)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottomTrailing)))
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: model.toast)
        .sheet(isPresented: $model.showingCapture) { CaptureView(model: model) }
        .sheet(isPresented: $model.showingTranscription) {
            if #available(macOS 26.0, *) { TranscriptionView(model: model) }
        }
        .alert("BigBrain", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .onAppear { model.start() }
    }
}

@main
struct BigBrainApp: App {
    @StateObject private var model = BrainModel()
    var body: some Scene {
        Window(Distribution.store ? "BigBrain Studio" : "BigBrain Agent", id: "main") { RootView(model: model) }
            .defaultSize(width: 1150, height: 760)
            .windowStyle(.hiddenTitleBar)
            .commands {
                CommandGroup(replacing: .newItem) {
                    Button("Fånga snabbt") { model.showingCapture = true }.keyboardShortcut("n", modifiers: .command)
                        .disabled(model.editorHit != nil)
                    Button(model.editorHit == nil ? "Sök i biblioteket" : "Sök källor och kommandon",
                           action: model.openSearchCommand).keyboardShortcut("k", modifiers: .command)
                }
                CommandGroup(after: .importExport) {
                    Button("Importera från iPhone…") { model.choosePhoneCapture() }.disabled(model.importing || model.editorHit != nil)
                }
            }
    }
}
