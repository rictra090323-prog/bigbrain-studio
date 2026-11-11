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

    init(model: BrainModel, hit: Hit, note: Note) {
        self.model = model
        self.hit = hit
        self.note = note
        _baseline = State(initialValue: note)
        _draft = State(initialValue: note.body)
        _draftRevision = State(initialValue: note.revision)
    }

    private var dirty: Bool { draft != baseline.body }
    private var conflicting: Bool { draftRevision != baseline.revision || note.revision != baseline.revision }

    var body: some View {
        let visibleText = raw ? draft : editor.view.flatMap { $0.markdownMode ? nil : $0.string }
            ?? StudioMarkdown.read(draft).string
        return VStack(alignment: .leading, spacing: 9) {
            documentToolbar
            HStack(spacing: 18) {
                if showOutline && !raw { outline }
                StudioTextEditor(markdown: draft, raw: raw, busy: busy, control: editor, onChange: updateDraft)
                    .id(raw)
                    .padding(.horizontal, 19)
                    .padding(.vertical, 14)
                    .frame(maxWidth: 840, maxHeight: .infinity)
                    .background(Color(red: 0.08, green: 0.105, blue: 0.16), in: RoundedRectangle(cornerRadius: 14))
                    .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.12)).allowsHitTesting(false) }
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
                Text(hit.title).font(.title2.weight(.semibold)).lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(model.studioFocus ? "Avsluta helskärm" : "Helskärm",
                       systemImage: model.studioFocus ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right") {
                    if model.studioFocus {
                        model.leaveStudioFocus()
                    } else {
                        model.enterStudioFocus(in: editor.view?.window)
                        editor.view?.window?.makeFirstResponder(editor.view)
                    }
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(busy)
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

    private func find(_ action: NSTextFinder.Action) {
        let item = NSMenuItem()
        item.tag = action.rawValue
        editor.view?.performTextFinderAction(item)
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
                    showOutline.toggle()
                }.disabled(raw)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 28)
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

private struct StudioToolbarBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 17))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 17))
        }
    }
}
