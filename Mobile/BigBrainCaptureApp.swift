import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

private typealias CaptureState<Value> = SwiftUI.State<Value>

extension SavedCapture: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: UTType(exportedAs: "se.richard.bigbrain.capture", conformingTo: .data)) {
            SentTransferredFile($0.file)
        }
    }
}

@main
struct BigBrainCaptureApp: App {
    var body: some Scene {
        WindowGroup { MobileCaptureView() }
    }
}

struct MobileCaptureView: View {
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var composing: Bool
    @CaptureState private var draft = ""
    @CaptureState private var entries: [SavedCapture] = []
    @CaptureState private var unreadable = 0
    @CaptureState private var error: String?
    @CaptureState private var voiceInProgress = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if #available(iOS 26.0, *) {
                        VoiceCapture(draft: $draft, inProgress: $voiceInProgress) { composing = false }
                    }
                    ZStack(alignment: .topLeading) {
                        if draft.isEmpty {
                            Text("Skriv en tanke eller något att komma ihåg…")
                                .foregroundStyle(.tertiary)
                                .padding(.leading, 5).padding(.top, 8)
                                .allowsHitTesting(false).accessibilityHidden(true)
                        }
                        TextEditor(text: $draft)
                            .scrollContentBackground(.hidden)
                            .focused($composing)
                            .frame(minHeight: 120)
                            .accessibilityLabel("Anteckningstext")
                    }
                    Button("Spara på enheten", action: save)
                        .disabled(voiceInProgress || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } header: {
                    Text("Ny anteckning")
                }
                Section {
                    if entries.isEmpty {
                        Text("Inga sparade anteckningar ännu.").foregroundStyle(.secondary)
                    }
                    ForEach(entries) { entry in
                        HStack {
                            Text(entry.capture.title).lineLimit(2)
                            Spacer()
                            ShareLink(item: entry, preview: SharePreview(entry.capture.title)) {
                                Image(systemName: "square.and.arrow.up")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Dela \(entry.capture.title)")
                        }
                    }
                    .onDelete(perform: remove)
                    if unreadable > 0 {
                        Text("En eller flera anteckningar gick inte att läsa. Filerna ligger kvar.")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Sparat på enheten")
                } footer: {
                    Text("Dela en anteckning via AirDrop. Öppna sedan Arkiv → Importera från iPhone i BigBrain Studio på din Mac.")
                }
            }
            .navigationTitle("Fånga")
        }
        .task { reload() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { reload() }
        }
        .alert("BigBrain", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    private func reload() {
        do {
            let result = try CaptureQueue.local().load()
            entries = result.entries
            unreadable = result.unreadable
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func save() {
        do {
            let entry = try CaptureQueue.local().save(draft)
            entries.insert(entry, at: 0)
            draft = ""
            composing = false
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func remove(at offsets: IndexSet) {
        let ids = offsets.map { entries[$0].id }
        do {
            let queue = try CaptureQueue.local()
            for id in ids {
                try queue.remove(id)
                entries.removeAll { $0.id == id }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}


@available(iOS 26.0, *)
private struct VoiceCapture: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var session = TranscriptionSession()
    @Binding var draft: String
    @Binding var inProgress: Bool
    let hideKeyboard: () -> Void

    private var active: Bool { session.recording || session.working }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(session.recording ? "Stoppa och transkribera" : "Spela in röstanteckning",
                       systemImage: session.recording ? "stop.circle.fill" : "mic") {
                    if session.recording {
                        session.stopRecording()
                    } else {
                        hideKeyboard()
                        session.startRecording(locale: .current)
                    }
                }
                .buttonStyle(.borderless)
                .disabled(session.working)
                Spacer()
                if active {
                    Button("Avbryt", action: session.cancel).buttonStyle(.borderless)
                }
            }
            if !session.status.isEmpty {
                Text(session.status).font(.footnote).foregroundStyle(.secondary)
            }
            if let error = session.error {
                Text(error).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .onChange(of: active) { _, active in inProgress = active }
        .onChange(of: session.draft) { _, transcript in
            guard !transcript.isEmpty else { return }
            draft += draft.isEmpty ? transcript : "\n\n" + transcript
            session.draft = ""
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background && session.recording { session.stopRecording() }
        }
        .onDisappear {
            session.cancel()
            inProgress = false
        }
    }
}
