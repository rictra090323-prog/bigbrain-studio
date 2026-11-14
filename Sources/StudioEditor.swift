import AppKit
import CryptoKit
import SwiftUI

final class StudioEditorControl: ObservableObject {
    weak var view: StudioTextView?
}

struct StudioTextEditor: NSViewRepresentable {
    let markdown: String
    let raw: Bool
    let busy: Bool
    let control: StudioEditorControl
    let onChange: (String) -> Void
    let openCitation: (StudioCitation) -> Void

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: StudioTextEditor
        var rendered: String?
        init(_ parent: StudioTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? StudioTextView, let storage = view.textStorage else { return }
            let output = parent.raw ? view.string : StudioMarkdown.write(storage)
            rendered = output
            parent.onChange(output)
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let storage = textView.textStorage, charIndex < storage.length else { return false }
            if let markup = storage.attribute(StudioCitation.attribute, at: charIndex, effectiveRange: nil) as? String,
               let citation = StudioCitation(markup: markup) {
                parent.openCitation(citation)
                return true
            }
            if let markup = storage.attribute(StudioWebLink.attribute, at: charIndex, effectiveRange: nil) as? String,
               let webLink = StudioWebLink(markup: markup) {
                NSWorkspace.shared.open(webLink.url)
                return true
            }
            return false
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        let editor = StudioTextView(frame: scroll.bounds)
        editor.isRichText = !raw
        editor.markdownMode = raw
        editor.importsGraphics = false
        editor.allowsUndo = true
        editor.usesFindBar = true
        editor.isIncrementalSearchingEnabled = true
        editor.drawsBackground = false
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainerInset = NSSize(width: 23, height: 14)
        editor.setAccessibilityLabel("Anteckningstext")
        editor.delegate = context.coordinator
        scroll.documentView = editor
        control.view = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? StudioTextView else { return }
        context.coordinator.parent = self
        editor.isEditable = !busy
        guard context.coordinator.rendered != markdown else { return }
        let range = editor.selectedRange()
        let text = raw
            ? NSAttributedString(string: markdown, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
                                                                .foregroundColor: NSColor.labelColor])
            : StudioMarkdown.read(markdown)
        editor.textStorage?.setAttributedString(text)
        editor.typingAttributes = raw ? [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
                                          .foregroundColor: NSColor.labelColor] : StudioMarkdown.style()
        editor.setSelectedRange(NSRange(location: min(range.location, text.length), length: 0))
        editor.undoManager?.removeAllActions(withTarget: editor)
        context.coordinator.rendered = markdown
    }
}

private struct StudioDraft: Codable {
    let revision: String
    let text: String

    static func url(for note: Note) throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        let directory = support.appendingPathComponent("BigBrain Studio/Drafts", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let key = SHA256.hash(data: Data(note.file.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(key + ".json")
    }
}

private struct StudioSuggestion: Decodable, Sendable {
    let hit: Hit
    let revision: String
    let excerpt: String
    let terms: [String]
}

struct StudioNoteView: View {
    private enum ToolTab: String, CaseIterable {
        case start = "Start", export = "Exportera", view = "Visa"
    }

    @ObservedObject var model: BrainModel
    let hit: Hit
    let note: Note
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var editor = StudioEditorControl()
    @LocalState private var baseline: Note
    @LocalState private var draft: String
    @LocalState private var draftRevision: String
    @LocalState private var raw = false
    @LocalState private var toolTab = ToolTab.start
    @LocalState private var loaded = false
    @LocalState private var busy = false
    @LocalState private var searching = false
    @LocalState private var suggestion: StudioSuggestion?
    @LocalState private var lookupStatus = ""
    @LocalState private var failure = ""
    @LocalState private var beforeLink: String?
    @LocalState private var thread: CGFloat = 0
    @LocalState private var replaceDraft = false
    @LocalState private var showOutline = false
    @LocalState private var research: StudioResearchMode?
    @LocalState private var researchQuery = ""
    @LocalState private var researchFocusRequest = 0
    @LocalState private var insertion: StudioInsertion?

    init(model: BrainModel, hit: Hit, note: Note, citation: StudioCitation? = nil) {
        self.model = model
        self.hit = hit
        self.note = note
        _baseline = State(initialValue: note)
        _draft = State(initialValue: note.body)
        _draftRevision = State(initialValue: note.revision)
        _research = State(initialValue: citation.map(StudioResearchMode.citation))
    }

    private var dirty: Bool { draft != baseline.body }
    private var conflicting: Bool { draftRevision != baseline.revision || note.revision != baseline.revision }

    var body: some View {
        let visibleText = raw ? draft : editor.view.flatMap { $0.markdownMode ? nil : $0.string }
            ?? StudioMarkdown.read(draft).string
        return VStack(alignment: .leading, spacing: 9) {
            documentToolbar
            HStack(spacing: 18) {
                if showOutline && !raw && research == nil { outline }
                StudioTextEditor(markdown: draft, raw: raw, busy: busy, control: editor, onChange: updateDraft,
                                 openCitation: { research = .citation($0) })
                    .id(raw)
                    .padding(.horizontal, 19)
                    .padding(.vertical, 14)
                    .frame(maxWidth: 840, maxHeight: .infinity)
                    .background(Color(red: 0.08, green: 0.105, blue: 0.16), in: RoundedRectangle(cornerRadius: 14))
                    .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.12)).allowsHitTesting(false) }
                if let research {
                    StudioResearchPanel(document: note, mode: research, query: $researchQuery, revision: baseline.revision,
                                        focusRequest: researchFocusRequest,
                                        setMode: { mode in
                                            if let mode { self.research = mode } else { closeResearch() }
                                        }, insertCitation: insertCitation,
                                        restore: restoreVersion, findInDocument: { closeResearch(); find(.showFindInterface) },
                                        canRestore: !dirty && !conflicting && !busy)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let suggestion { connection(suggestion) }
            if !lookupStatus.isEmpty { Text(lookupStatus).font(.caption).foregroundStyle(.secondary) }
            if !failure.isEmpty { Text(failure).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
            HStack {
                Text(busy ? "Sparar…" : conflicting ? "Sparad version har ändrats" : dirty ? "Osparade ändringar" : "Sparat lokalt")
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("studio-save-status")
                Spacer()
                Text("\(visibleText.split(whereSeparator: \.isWhitespace).count.formatted()) ord · \(visibleText.count.formatted()) tecken")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                if conflicting {
                    Button("Kopiera utkast") { model.copy(draft) }
                    Button("Hämta sparad") { replaceDraft = true }
                } else {
                    Button("Visa fil") { model.reveal(note.path) }.buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 27)
        .padding(.top, 32)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear(perform: restoreDraft)
        .onChange(of: model.editorCommandRequest) { _, _ in openResearch() }
        .sheet(item: $insertion, onDismiss: { editor.view?.window?.makeFirstResponder(editor.view) }) { insertion in
            switch insertion {
            case .link(let label):
                StudioLinkSheet(label: label) { link in
                    editor.view?.insertWebLink(link)
                    BrainHaptics.action()
                }
            case .table(let table, let range):
                StudioTableSheet(table: table, editing: range != nil) { table in
                    editor.view?.insertMarkdownBlock(table.markdown, replacing: range)
                    BrainHaptics.action()
                }
            }
        }
        .alert("Byt till den sparade versionen?", isPresented: $replaceDraft) {
            Button("Avbryt", role: .cancel) {}
            Button("Hämta sparad", role: .destructive) {
                baseline = note
                draftRevision = note.revision
                updateDraft(note.body)
            }
        } message: { Text("Kopiera utkastet först om du vill behålla dina ändringar.") }
    }

    private var documentToolbar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button("Tillbaka", systemImage: "chevron.left", action: model.closeEditor)
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(busy)
                let appearance = model.appearance(for: hit)
                Image(systemName: appearance.symbol.icon).foregroundStyle(appearance.accent.tint)
                    .accessibilityHidden(true)
                Text(hit.title).font(.title2.weight(.semibold)).lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Spara") { commit(draft) }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!dirty || busy || conflicting)
                    .buttonStyle(.borderedProminent)
            }
            Divider()
            HStack {
                Picker("Skrivverktyg", selection: $toolTab) {
                    ForEach(ToolTab.allCases, id: \.self) { tab in Text(tab.rawValue).tag(tab) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
                Button("Källor", systemImage: "text.magnifyingglass", action: openResearch)
                    .help("Sök i biblioteket och infoga en hänvisning (⌘K)")
                    .disabled(busy)
                Menu {
                    Button("Sök i anteckningen") { find(.showFindInterface) }
                        .keyboardShortcut("f", modifiers: .command)
                    Button("Sök och ersätt") { find(.showReplaceInterface) }
                        .keyboardShortcut("f", modifiers: [.command, .option])
                        .disabled(busy)
                } label: { Label("Sök", systemImage: "magnifyingglass") }
                .fixedSize()
            }
            tools
        }
        .padding(13)
        .modifier(StudioToolbarBackground())
    }

    private func openResearch() {
        guard !busy else { return }
        if research == nil, let selection = editor.view?.lookupText.trimmingCharacters(in: .whitespacesAndNewlines) {
            researchQuery = String(selection.prefix(240))
        }
        research = .sources
        researchFocusRequest += 1
    }

    private func closeResearch() {
        research = nil
        if let view = editor.view { view.window?.makeFirstResponder(view) }
    }

    private func restoreVersion(_ body: String) {
        guard !dirty, !conflicting, !busy else { return }
        updateDraft(body)
        closeResearch()
    }

    private func insertCitation(_ args: [String]) async throws {
        guard !busy, !conflicting, let view = editor.view else {
            throw BackendFailure(message: "Spara eller lös konflikten i dokumentet innan du lägger till hänvisningen.")
        }
        let savedDraft = draft
        let position = NSMaxRange(view.selectedRange())
        let result: StudioCitationResponse = try await Bridge.invoke(args)
        guard research == .sources, !Task.isCancelled, !busy, !conflicting,
              draft == savedDraft, editor.view === view else {
            throw BackendFailure(message: "Dokumentet ändrades. Välj utdraget igen för att infoga hänvisningen.")
        }
        guard let citation = StudioCitation(markup: result.markdown) else {
            throw BackendFailure(message: "Hänvisningen kunde inte läsas.")
        }
        view.insertCitation(citation, at: position)
        research = .citation(citation)
    }

    private func find(_ action: NSTextFinder.Action) {
        editor.view?.showFindInterface(action)
    }

    private var outline: some View {
        let text = StudioMarkdown.read(draft)
        let headings = text.string.components(separatedBy: "\n").reduce(into: (offset: 0, rows: [(Int, String, Int)]())) { output, title in
            let location = output.offset
            let length = (title as NSString).length
            output.offset += length + 1
            guard length > 0 else { return }
            let kind = StudioMarkdown.paragraph(text.attribute(StudioMarkdown.block, at: location, effectiveRange: nil))
            switch kind {
            case .heading: output.rows.append((location, title, 0))
            case .subheading: output.rows.append((location, title, 1))
            case .smallHeading: output.rows.append((location, title, 2))
            default: break
            }
        }.rows
        return VStack(alignment: .leading, spacing: 9) {
            Text("Rubriker").font(.headline).accessibilityAddTraits(.isHeader)
            if headings.isEmpty {
                Text("Använd rubrikformaten för att kunna hoppa mellan avsnitt.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(headings, id: \.0) { heading in
                        Button {
                            let position = NSRange(location: heading.0, length: 0)
                            guard let view = editor.view, position.location <= (view.string as NSString).length else { return }
                            view.setSelectedRange(position)
                            view.scrollRangeToVisible(position)
                            view.window?.makeFirstResponder(view)
                        } label: {
                            Text(heading.1).lineLimit(2).multilineTextAlignment(.leading)
                                .padding(.leading, CGFloat(heading.2) * 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(13)
        .frame(width: 190)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private var tools: some View {
        HStack(spacing: 8) {
            switch toolTab {
            case .start:
                insertMenu
                Divider().frame(height: 16)
                Menu("Format") {
                    ForEach(StudioParagraph.allCases, id: \.self) { paragraph in
                        Button(paragraph.rawValue) { editor.view?.changeParagraph(paragraph) }
                    }
                }.fixedSize().disabled(raw || busy)
                Button {
                    editor.view?.changeEmphasis(StudioMarkdown.bold)
                } label: {
                    Image(systemName: "bold")
                }
                .accessibilityLabel("Fetstil").help("Fetstil (⌘B)")
                .keyboardShortcut("b", modifiers: .command).disabled(raw || busy)
                Button {
                    editor.view?.changeEmphasis(StudioMarkdown.italic)
                } label: {
                    Image(systemName: "italic")
                }
                .accessibilityLabel("Kursiv").help("Kursiv (⌘I)")
                .keyboardShortcut("i", modifiers: .command).disabled(raw || busy)
                Button {
                    editor.view?.changeEmphasis(StudioMarkdown.underline)
                } label: {
                    Image(systemName: "underline")
                }
                .accessibilityLabel("Understrykning").help("Understrykning (⌘U)")
                .keyboardShortcut("u", modifiers: .command).disabled(raw || busy)
                Button {
                    editor.view?.changeEmphasis(StudioMarkdown.strike)
                } label: {
                    Image(systemName: "strikethrough")
                }
                .accessibilityLabel("Genomstrykning").help("Genomstrykning")
                .disabled(raw || busy)
                Divider().frame(height: 16)
                formatButton(.list, icon: "list.bullet")
                formatButton(.numbered, icon: "list.number")
                formatButton(.checklist, icon: "checklist")
                Button {
                    editor.view?.toggleChecklist()
                } label: {
                    Image(systemName: "checkmark.square")
                }
                .accessibilityLabel("Bocka av eller återställ raden")
                .help("Bocka av eller återställ den aktuella raden i en checklista (⇧⌘↩)")
                .keyboardShortcut(.return, modifiers: [.command, .shift])
                .disabled(raw || busy)
                Divider().frame(height: 16)
                Button {
                    editor.view?.undoManager?.undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }.accessibilityLabel("Ångra").help("Ångra")
                Button {
                    editor.view?.undoManager?.redo()
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                }.accessibilityLabel("Gör om").help("Gör om")
            case .export:
                ForEach(StudioExport.allCases, id: \.self) { format in
                    Button(format.label, systemImage: format.icon) {
                        format.save(markdown: draft, title: hit.title, in: editor.view?.window) { failure in
                            model.error = failure
                        }
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            case .view:
                Button(raw ? "Visa formaterat" : "Visa Markdown", systemImage: "chevron.left.forwardslash.chevron.right") {
                    raw.toggle()
                }
                Button(searching ? "Söker…" : "Visa samband", systemImage: "point.3.connected.trianglepath.dotted") {
                    findConnection()
                }
                .disabled(busy || searching).help("Utgår från markerad text eller stycket där du skriver")
                Button(showOutline ? "Dölj rubriker" : "Visa rubriker", systemImage: "list.bullet.indent") {
                    research = nil
                    showOutline.toggle()
                }.disabled(raw)
                Button("Versionshistorik", systemImage: "clock.arrow.circlepath") { research = .history }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 28)
    }

    private var insertMenu: some View {
        Menu {
            Button("Webblänk", systemImage: "link") {
                guard let view = editor.view, !view.selectedText.contains(where: \.isNewline) else {
                    failure = "Markera länktext på en enda rad eller placera markören där länken ska infogas."
                    return
                }
                insertion = .link(view.selectedText)
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
            Button("Infoga eller redigera tabell", systemImage: "tablecells") {
                let current = editor.view?.selectedTable
                insertion = .table(current?.table ?? StudioTable(), current?.range)
            }
            Button("Datum och tid", systemImage: "calendar") {
                guard let view = editor.view else { return }
                view.insertText(Date.now.formatted(date: .long, time: .shortened), replacementRange: view.selectedRange())
                view.window?.makeFirstResponder(view)
                BrainHaptics.action()
            }
            Button("Avdelare", systemImage: "minus") {
                editor.view?.insertMarkdownBlock("---")
                BrainHaptics.action()
            }
        } label: {
            Label("Infoga", systemImage: "plus")
        }
        .fixedSize()
        .disabled(busy)
        .accessibilityIdentifier("studio-insert-menu")
    }

    private func formatButton(_ paragraph: StudioParagraph, icon: String) -> some View {
        Button {
            editor.view?.changeParagraph(paragraph)
        } label: {
            Image(systemName: icon)
        }
        .accessibilityLabel(paragraph.rawValue).help(paragraph.rawValue)
        .disabled(raw || busy)
    }

    private func connection(_ suggestion: StudioSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(beforeLink == nil ? "Möjligt samband" : "Kopplat i Atlas").font(.subheadline.weight(.semibold))
                Spacer()
                Button("Dölj", systemImage: "xmark") { clearConnection() }.labelStyle(.iconOnly)
                    .buttonStyle(.plain).accessibilityLabel("Dölj samband")
            }
            Button(suggestion.hit.title) {
                model.show(.search)
                model.select(suggestion.hit, train: false)
            }
                .buttonStyle(.link).accessibilityLabel("Öppna " + suggestion.hit.title)
            Text(suggestion.excerpt).font(.callout).lineLimit(3).textSelection(.enabled)
            HStack(spacing: 9) {
                Text("Gemensamma ord · " + suggestion.terms.joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Spacer(minLength: 5)
                if let beforeLink {
                    Button("Ångra koppling") { commit(beforeLink, undo: true) }
                        .disabled(dirty || conflicting || busy)
                    Button("Visa i Atlas") {
                        model.show(.atlas)
                        model.select(hit, train: false)
                    }
                } else {
                    Button("Koppla i Atlas") { commit(draft, link: suggestion) }.disabled(conflicting || busy)
                }
            }
            GeometryReader { geometry in
                let start = CGPoint(x: 5, y: 10)
                let end = CGPoint(x: geometry.size.width - 5, y: 5)
                let line = Path { path in
                    path.move(to: start)
                    path.addQuadCurve(to: end, control: CGPoint(x: geometry.size.width * 0.65, y: 15))
                }
                line.stroke(.mint.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                line.trim(from: 0, to: thread).stroke(.mint, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                Circle().fill(.mint).frame(width: 6, height: 6).position(start)
                Circle().fill(.mint.opacity(beforeLink == nil ? 0.45 : 1)).frame(width: 6, height: 6).position(end)
            }.frame(height: 16).accessibilityHidden(true)
        }.padding(10).background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
    }

    private func restoreDraft() {
        guard !loaded else { return }
        loaded = true
        guard let url = try? StudioDraft.url(for: note), let bytes = try? Data(contentsOf: url),
              let saved = try? JSONDecoder().decode(StudioDraft.self, from: bytes), saved.text != note.body else { return }
        draft = saved.text
        draftRevision = saved.revision
    }

    private func updateDraft(_ text: String) {
        draft = text
        failure = ""
        if beforeLink == nil { clearConnection() }
        persistDraft()
    }

    private func persistDraft() {
        do {
            let url = try StudioDraft.url(for: note)
            if draft == baseline.body && draftRevision == baseline.revision {
                if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            } else {
                let data = try JSONEncoder().encode(StudioDraft(revision: draftRevision, text: draft))
                try data.write(to: url, options: .atomic)
            }
        } catch {
            failure = "Utkastet kunde inte sparas. Kopiera texten eller spara anteckningen innan du stänger."
        }
    }

    private func clearConnection() {
        suggestion = nil
        lookupStatus = ""
        beforeLink = nil
        thread = 0
    }

    private func findConnection() {
        let query = editor.view?.lookupText.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        clearConnection()
        guard !query.isEmpty else { lookupStatus = "Klicka i ett stycke eller markera text först."; return }
        let original = draft
        searching = true
        Task {
            defer { searching = false }
            do {
                let found: StudioSuggestion? = try await Bridge.invoke(["suggest-link", "--", note.path],
                                                                          input: Data(query.prefix(700).utf8))
                guard draft == original else { return }
                suggestion = found
                if found == nil { lookupStatus = "Hittade inget tydligt samband. Prova ett annat stycke." }
            } catch {
                lookupStatus = error.localizedDescription
            }
        }
    }

    private func commit(_ text: String, link: StudioSuggestion? = nil, undo: Bool = false) {
        guard !busy, !conflicting else { return }
        busy = true
        failure = ""
        let expected = baseline
        let savedDraft = draft
        let args: [String]
        if let link {
            args = ["confirm-link", "--expected-file=" + expected.file, "--", expected.path, expected.revision,
                    link.hit.path, link.revision]
        } else {
            args = ["save-note", "--expected-file=" + expected.file, "--", expected.path, expected.revision, "-"]
        }
        Task {
            defer { busy = false }
            do {
                let updated: Note = try await Bridge.invoke(args, input: Data(text.utf8))
                BrainHaptics.action()
                baseline = updated
                draftRevision = updated.revision
                draft = updated.body
                if let url = try? StudioDraft.url(for: expected), let bytes = try? Data(contentsOf: url),
                   let staged = try? JSONDecoder().decode(StudioDraft.self, from: bytes),
                   staged.text == savedDraft && staged.revision == expected.revision {
                    try? FileManager.default.removeItem(at: url)
                }
                model.acceptStudioEdit(updated, replacing: expected)
                if link != nil {
                    beforeLink = text
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.4)) { thread = 1 }
                } else if undo {
                    clearConnection()
                    lookupStatus = "Kopplingen togs bort."
                } else {
                    clearConnection()
                }
                await model.refresh(quiet: true)
            } catch {
                failure = error.localizedDescription
                if let latest: Note = try? await Bridge.invoke(["note", "--", expected.path]),
                   latest.file == expected.file, latest.revision != expected.revision {
                    baseline = latest
                    model.acceptStudioEdit(latest, replacing: expected)
                }
            }
        }
    }
}

private enum StudioInsertion: Identifiable {
    case link(String)
    case table(StudioTable, NSRange?)

    var id: Int {
        switch self {
        case .link: 0
        case .table: 1
        }
    }
}

private struct StudioLinkSheet: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var addressFocused: Bool
    @LocalState var label: String
    @LocalState private var address = ""
    let insert: (StudioWebLink) -> Void

    var body: some View {
        let link = StudioWebLink(title: label, address: address)
        VStack(alignment: .leading, spacing: 12) {
            Text("Infoga webblänk").font(.title2.weight(.semibold))
            TextField("Länktext", text: $label)
            TextField("Webbadress, t.ex. https://example.com", text: $address).focused($addressFocused)
            HStack {
                Spacer()
                Button("Avbryt", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Infoga") {
                    if let link { insert(link); dismiss() }
                }.keyboardShortcut(.defaultAction).disabled(link == nil)
            }
        }
        .padding(20).frame(width: 420)
        .onAppear { addressFocused = !label.isEmpty }
    }
}

private struct StudioTableSheet: View {
    @Environment(\.dismiss) private var dismiss
    @LocalState var table: StudioTable
    let editing: Bool
    let insert: (StudioTable) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(editing ? "Redigera tabell" : "Infoga tabell").font(.title2.weight(.semibold))
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(table.rows.indices, id: \.self) { row in
                        HStack(spacing: 7) {
                            ForEach(table.alignment.indices, id: \.self) { column in
                                let label = row == 0 ? "Rubrik \(column + 1)" : "Rad \(row), kolumn \(column + 1)"
                                TextField(row == 0 ? label : "Cell", text: $table.rows[row][column])
                                    .font(row == 0 ? .body.weight(.semibold) : .body)
                                    .frame(width: 145).accessibilityLabel(label)
                            }
                            if row > 0 {
                                Button("Ta bort rad \(row)", systemImage: "minus.circle") { table.rows.remove(at: row) }
                                    .labelStyle(.iconOnly).buttonStyle(.borderless)
                            }
                        }
                    }
                }.padding(2)
            }
            .frame(minHeight: 95, maxHeight: 250)
            HStack {
                Button("Rad", systemImage: "plus") { table.rows.append(Array(repeating: "", count: table.alignment.count)) }
                    .disabled(table.rows.count >= 50)
                Button("Kolumn", systemImage: "plus") { table.addColumn() }.disabled(table.alignment.count >= 12)
                Button("Kolumn", systemImage: "minus") { table.removeColumn() }.disabled(table.alignment.count <= 1)
                Spacer()
                Button("Avbryt", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(editing ? "Uppdatera" : "Infoga") { insert(table); dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20).frame(width: 565)
    }
}

private struct StudioToolbarBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 17))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 17))
        }
    }
}


private enum StudioResearchMode: Equatable {
    case sources
    case history
    case citation(StudioCitation)
}

private struct StudioPassage: Decodable, Identifiable {
    let start: Int
    let length: Int
    let text: String
    var id: Int { start }
}

private struct StudioSourcePreview: Decodable {
    let revision: String
    let passages: [StudioPassage]
}

private struct StudioCitationResponse: Decodable {
    let markdown: String
}

private struct StudioArchivedSource: Decodable {
    let path: String
    let revision: String
    let body: String
    let excerpt: String
}

private struct StudioHistoryEvent: Decodable, Identifiable {
    let id: Int
    let author: String
    let saved: String
    let reason: String

    var authorLabel: String {
        switch author {
        case "writer": "Egen ändring"
        case "agent": "Godkänt agentförslag"
        default: "Godkänt ändringsförslag"
        }
    }

    var dateLabel: String {
        (try? Date.ISO8601FormatStyle().parse(saved))?
            .formatted(date: .abbreviated, time: .shortened) ?? saved
    }
}

private struct StudioHistoryDetail: Decodable {
    let body: String
    let before: String?
    let diff: String
}

private struct StudioResearchPanel: View {
    let document: Note
    let mode: StudioResearchMode
    @Binding var query: String
    let revision: String
    let focusRequest: Int
    let setMode: (StudioResearchMode?) -> Void
    let insertCitation: ([String]) async throws -> Void
    let restore: (String) -> Void
    let findInDocument: () -> Void
    let canRestore: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Källor och versioner").font(.headline).accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Stäng", systemImage: "xmark") { setMode(nil) }
                    .labelStyle(.iconOnly).buttonStyle(.plain)
            }
            HStack {
                Button("Källor", systemImage: "text.magnifyingglass") { setMode(.sources) }
                Button("Historik", systemImage: "clock.arrow.circlepath") { setMode(.history) }
                Button("Sök i text", systemImage: "magnifyingglass", action: findInDocument)
            }
            Divider()
            switch mode {
            case .sources:
                StudioSourcesView(document: document, query: $query, focusRequest: focusRequest, insertCitation: insertCitation)
            case .history:
                StudioHistoryView(document: document, revision: revision, restore: restore, canRestore: canRestore)
            case .citation(let citation):
                StudioArchiveView(document: document, citation: citation)
            }
        }
        .padding(14)
        .frame(width: 345)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
        .onKeyPress(.escape) { setMode(nil); return .handled }
    }
}

private struct StudioSourcesView: View {
    let document: Note
    @Binding var query: String
    let focusRequest: Int
    let insertCitation: ([String]) async throws -> Void
    @LocalState private var results: [Hit] = []
    @LocalState private var resultTerm: String?
    @LocalState private var selected: Hit?
    @LocalState private var preview: StudioSourcePreview?
    @LocalState private var error = ""
    @LocalState private var inserting = false
    @FocusState private var queryFocused: Bool

    private var term: String { String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240)) }

    var body: some View {
        let queryTerm = term
        VStack(alignment: .leading, spacing: 10) {
            TextField("Sök i biblioteket", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($queryFocused)
                .onAppear { queryFocused = true }
                .onChange(of: focusRequest) { _, _ in queryFocused = true }
                .onSubmit {
                    if let first = results.first, resultTerm == queryTerm { select(first) }
                }
            if !error.isEmpty { Text(error).font(.callout).foregroundStyle(.orange) }
            if let selected {
                Button("Tillbaka till träffarna", systemImage: "chevron.left") { self.selected = nil }
                    .buttonStyle(.plain)
                Text(selected.title).font(.title3.weight(.semibold))
                Text(selected.path).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                if let preview {
                    if preview.passages.isEmpty {
                        Text("Källan innehåller ingen text.").foregroundStyle(.secondary)
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(preview.passages) { passage in
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(passage.text).textSelection(.enabled)
                                    Button("Infoga hänvisning", systemImage: "link") { insert(selected, preview, passage) }
                                        .disabled(inserting)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 9))
                            }
                        }
                    }
                } else if error.isEmpty {
                    ProgressView().controlSize(.small)
                }
            } else if queryTerm.isEmpty {
                Text("Sök efter ett ämne eller en källtitel.").foregroundStyle(.secondary)
            } else if resultTerm != queryTerm && error.isEmpty {
                ProgressView().controlSize(.small)
            } else if results.isEmpty && error.isEmpty {
                Text("Inga källor hittades.").foregroundStyle(.secondary)
            } else if resultTerm == queryTerm {
                ScrollView {
                    VStack(spacing: 5) {
                        ForEach(results) { hit in
                            Button { select(hit) } label: { HitCell(hit: hit, active: false) }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .task(id: queryTerm) { await search(queryTerm) }
        .task(id: selected?.id) {
            if let hit = selected { await load(hit, queryTerm) }
        }
        .onChange(of: queryTerm) { _, _ in selected = nil }
    }

    private func select(_ hit: Hit) {
        guard selected?.id != hit.id else { return }
        error = ""
        preview = nil
        selected = hit
    }

    private func search(_ queryTerm: String) async {
        error = ""
        guard !queryTerm.isEmpty else { return }
        do {
            try await Task.sleep(for: .milliseconds(220))
            let hits: [Hit] = try await Bridge.invoke(arguments("source-search") + [queryTerm])
            guard !Task.isCancelled, term == queryTerm else { return }
            results = hits
            resultTerm = queryTerm
        } catch {
            guard !Task.isCancelled, term == queryTerm else { return }
            self.error = error.localizedDescription
        }
    }

    private func load(_ hit: Hit, _ queryTerm: String) async {
        do {
            let result: StudioSourcePreview = try await Bridge.invoke(arguments("source-preview") + [hit.path, hit.file, queryTerm])
            guard !Task.isCancelled, selected?.id == hit.id, term == queryTerm else { return }
            preview = result
        } catch {
            guard !Task.isCancelled, selected?.id == hit.id, term == queryTerm else { return }
            self.error = error.localizedDescription
        }
    }

    private func insert(_ hit: Hit, _ preview: StudioSourcePreview, _ passage: StudioPassage) {
        inserting = true
        error = ""
        Task {
            defer { inserting = false }
            do {
                try await insertCitation(arguments("source-cite") + [hit.path, hit.file, preview.revision,
                                                                     String(passage.start), String(passage.length)])
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func arguments(_ command: String) -> [String] {
        [command, "--expected-file=" + document.file, "--", document.path]
    }
}

private struct StudioArchiveView: View {
    let document: Note
    let citation: StudioCitation
    @LocalState private var source: StudioArchivedSource?
    @LocalState private var error = ""
    @LocalState private var fullText = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(citation.title).font(.title3.weight(.semibold))
            if let source {
                Text(source.path).font(.caption).foregroundStyle(.secondary)
                Label("Sparad källversion · \(source.revision.prefix(10))", systemImage: "checkmark.seal")
                    .font(.caption).foregroundStyle(.secondary)
                ScrollView {
                    Text(fullText ? source.body : source.excerpt)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                Button(fullText ? "Visa utdraget" : "Läs hela källversionen") { fullText.toggle() }
            } else if !error.isEmpty {
                Text(error).foregroundStyle(.orange)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task(id: citation) {
            source = nil
            error = ""
            fullText = false
            do {
                let args = ["source-version", "--expected-file=" + document.file, "--", document.path,
                            citation.relativePath, citation.revision, String(citation.start), String(citation.length)]
                let result: StudioArchivedSource = try await Bridge.invoke(args)
                if !Task.isCancelled { source = result }
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
    }
}

private struct StudioHistoryView: View {
    let document: Note
    let revision: String
    let restore: (String) -> Void
    let canRestore: Bool
    @LocalState private var events: [StudioHistoryEvent]?
    @LocalState private var selection: StudioHistoryEvent?
    @LocalState private var detail: StudioHistoryDetail?
    @LocalState private var error = ""
    @LocalState private var showVersion = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let selection {
                Button("Tillbaka till historiken", systemImage: "chevron.left") { self.selection = nil; error = "" }
                    .buttonStyle(.plain)
                Text(selection.authorLabel).font(.headline)
                Text(selection.dateLabel).font(.caption).foregroundStyle(.secondary)
                if let detail {
                    ScrollView {
                        Text(showVersion ? detail.body : detail.diff)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    Button(showVersion ? "Visa ändringar" : "Visa hela versionen") { showVersion.toggle() }
                    Button("Använd som utkast") { restore(detail.body) }
                        .disabled(!canRestore || detail.body.isEmpty)
                    if let before = detail.before, !before.isEmpty {
                        Button("Använd föregående text som utkast") { restore(before) }.disabled(!canRestore)
                    }
                } else if error.isEmpty {
                    ProgressView().controlSize(.small)
                }
            } else if let events {
                if events.isEmpty {
                    Text("Sparningar och godkända förslag visas här.").foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 7) {
                            ForEach(events) { event in
                                Button {
                                    detail = nil
                                    error = ""
                                    showVersion = false
                                    selection = event
                                } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(event.authorLabel).font(.callout.weight(.semibold))
                                        Text(event.dateLabel).font(.caption).foregroundStyle(.secondary)
                                        if !event.reason.isEmpty {
                                            Text(event.reason).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
            } else if error.isEmpty {
                ProgressView().controlSize(.small)
            }
            if !error.isEmpty { Text(error).foregroundStyle(.orange) }
        }
        .task(id: revision) {
            do {
                let result: [StudioHistoryEvent] = try await Bridge.invoke(arguments("note-history"))
                if !Task.isCancelled { events = result }
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
        .task(id: selection?.id) {
            guard let event = selection else { return }
            do {
                let result: StudioHistoryDetail = try await Bridge.invoke(arguments("history-entry") + [String(event.id)])
                if !Task.isCancelled, selection?.id == event.id { detail = result }
            } catch {
                if !Task.isCancelled, selection?.id == event.id { self.error = error.localizedDescription }
            }
        }
    }

    private func arguments(_ command: String) -> [String] {
        [command, "--expected-file=" + document.file, "--", document.path]
    }
}
