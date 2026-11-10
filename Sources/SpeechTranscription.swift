import AVFoundation
import Foundation
import Speech
import SwiftUI

private struct TranscriptionFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@available(macOS 26.0, iOS 26.0, *)
enum LocalTranscription {
    static let maximumDuration: TimeInterval = 60 * 60

    static func transcribe(_ url: URL, locale: Locale,
                           status: @MainActor @Sendable (String) -> Void = { _ in }) async throws -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let file: AVAudioFile
        do { file = try AVAudioFile(forReading: url) }
        catch { throw TranscriptionFailure(message: "Ljudfilen kunde inte läsas. Välj exempelvis en M4A-, MP3- eller WAV-fil.") }
        let duration = Double(file.length) / file.processingFormat.sampleRate
        guard duration.isFinite, duration > 0 else {
            throw TranscriptionFailure(message: "Ljudfilen är tom.")
        }
        guard duration <= maximumDuration + 1 else {
            throw TranscriptionFailure(message: "Ljudfilen får vara högst en timme.")
        }

        if SpeechTranscriber.isAvailable,
           let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
            let module = SpeechTranscriber(locale: supported, preset: .transcription)
            return try await analyze(file, with: module, status: status) { String($0.text.characters) }
        }
        if let supported = await DictationTranscriber.supportedLocale(equivalentTo: locale) {
            let module = DictationTranscriber(locale: supported, preset: .longDictation)
            return try await analyze(file, with: module, status: status) { String($0.text.characters) }
        }
        throw TranscriptionFailure(message: "Det valda språket stöds inte för lokal transkribering på den här enheten.")
    }

    private static func analyze<M: SpeechModule>(_ file: AVAudioFile, with module: M,
                                                 status: @MainActor @Sendable (String) -> Void,
                                                 text: @escaping @Sendable (M.Result) -> String) async throws -> String {
        try Task.checkCancellation()
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            await status("Hämtar Apples språkmodell…")
            do { try await request.downloadAndInstall() }
            catch {
                try Task.checkCancellation()
                throw TranscriptionFailure(message: "Språkmodellen kunde inte hämtas. Försök igen när enheten är ansluten.")
            }
        }
        try Task.checkCancellation()
        await status("Transkriberar på den här enheten…")
        let analyzer = SpeechAnalyzer(modules: [module])
        return try await withTaskCancellationHandler {
            async let transcript = collect(module, text: text)
            do {
                try Task.checkCancellation()
                try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
                let result = try await transcript
                try Task.checkCancellation()
                guard !result.isEmpty else {
                    throw TranscriptionFailure(message: "Inget tal kunde transkriberas från ljudet.")
                }
                return result
            } catch {
                await analyzer.cancelAndFinishNow()
                throw error
            }
        } onCancel: {
            Task { await analyzer.cancelAndFinishNow() }
        }
    }

    private static func collect<M: SpeechModule>(_ module: M,
                                                 text: @Sendable (M.Result) -> String) async throws -> String {
        var passages: [String] = []
        for try await result in module.results where result.isFinal {
            let passage = text(result).trimmingCharacters(in: .whitespacesAndNewlines)
            if !passage.isEmpty { passages.append(passage) }
        }
        return passages.joined(separator: " ")
    }
}

@available(macOS 26.0, iOS 26.0, *)
@MainActor
final class TranscriptionSession: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var draft = ""
    @Published private(set) var status = ""
    @Published private(set) var error: String?
    @Published private(set) var recording = false
    @Published private(set) var working = false

    private var recorder: AVAudioRecorder?
    private var recordingFolder: URL?
    private var recordingLocale = Locale(identifier: "sv-SE")
    private var task: Task<Void, Never>?
    private var operation = UUID()
    #if os(iOS)
    private var audioSessionActive = false
    #endif

    func startRecording(locale: Locale) {
        guard !recording && !working else { return }
        let id = UUID()
        operation = id
        recordingLocale = locale
        error = nil
        working = true
        status = "Väntar på mikrofonen…"
        task = Task {
            let granted = await AVAudioApplication.requestRecordPermission()
            guard id == operation && !Task.isCancelled else { return }
            defer { working = false; task = nil }
            guard granted else {
                error = "Ge BigBrain åtkomst till mikrofonen i inställningarna."
                status = ""
                return
            }
            do {
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent("bigbrain-recording-" + id.uuidString)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false,
                                                        attributes: [.posixPermissions: 0o700])
                recordingFolder = folder
                let url = folder.appendingPathComponent("recording.m4a")
                #if os(iOS)
                let audio = AVAudioSession.sharedInstance()
                try audio.setCategory(.record, mode: .default)
                try audio.setActive(true)
                audioSessionActive = true
                #endif
                let device = try AVAudioRecorder(url: url, settings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100,
                    AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
                ])
                device.delegate = self
                guard device.record(forDuration: LocalTranscription.maximumDuration) else {
                    throw TranscriptionFailure(message: "Inspelningen kunde inte startas.")
                }
                recorder = device
                recording = true
                status = "Spelar in…"
            } catch {
                clearRecording()
                status = ""
                self.error = error.localizedDescription
            }
        }
    }

    func stopRecording() {
        guard let recorder else { return }
        recorder.stop()
        finishRecording(url: recorder.url, success: true)
    }

    func transcribe(_ url: URL, locale: Locale, remove folder: URL? = nil) {
        guard !recording && !working else { return }
        let id = UUID()
        operation = id
        error = nil
        working = true
        status = "Kontrollerar språkstöd…"
        task = Task {
            defer {
                if let folder { try? FileManager.default.removeItem(at: folder) }
                if operation == id { working = false; status = ""; task = nil }
            }
            do {
                let result = try await LocalTranscription.transcribe(url, locale: locale) { [weak self] message in
                    if self?.operation == id { self?.status = message }
                }
                guard operation == id && !Task.isCancelled else { return }
                draft += draft.isEmpty ? result : "\n\n" + result
            } catch is CancellationError {
                // The user can cancel without discarding the existing draft.
            } catch {
                if operation == id { self.error = error.localizedDescription }
            }
        }
    }

    func cancel() {
        operation = UUID()
        task?.cancel()
        task = nil
        clearRecording()
        working = false
        status = ""
    }

    private func clearRecording() {
        let active = recorder
        recorder = nil
        active?.stop()
        endAudioSession()
        if let recordingFolder { try? FileManager.default.removeItem(at: recordingFolder) }
        recordingFolder = nil
        recording = false
    }

    private func finishRecording(url: URL, success: Bool) {
        guard recorder?.url == url, let folder = recordingFolder else { return }
        if success {
            recorder = nil
            recordingFolder = nil
            recording = false
            endAudioSession()
            transcribe(url, locale: recordingLocale, remove: folder)
        } else {
            clearRecording()
            status = ""
            error = "Inspelningen kunde inte slutföras. Kontrollera mikrofonen och försök igen."
        }
    }

    private func endAudioSession() {
        #if os(iOS)
        guard audioSessionActive else { return }
        audioSessionActive = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        let url = recorder.url
        Task { @MainActor in finishRecording(url: url, success: flag) }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: (any Error)?) {
        let url = recorder.url
        Task { @MainActor in finishRecording(url: url, success: false) }
    }
}
