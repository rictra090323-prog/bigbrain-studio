import Foundation

@main
struct CaptureQueueSmoke {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("bigbrain-\(UUID())")
        let queue = CaptureQueue(directory: directory)
        defer { try? FileManager.default.removeItem(at: directory) }

        let empty = try queue.load()
        precondition(empty.entries.isEmpty && empty.unreadable == 0)
        do {
            _ = try queue.save(" \n ")
            preconditionFailure("Tom text gick att spara.")
        } catch CaptureQueueError.invalidText {}
        do {
            _ = try queue.save(String(repeating: "å", count: MobileCapture.textLimit / 2 + 1))
            preconditionFailure("För stor text gick att spara.")
        } catch CaptureQueueError.tooLong {}

        let text = "En snabbfångst från mobilen\nSökordet är jordgubbsnebulosa 🍓."
        let entry = try queue.save(text)
        try Data("{".utf8).write(to: directory.appendingPathComponent("skadad.bbcapture"))
        let reopened = try CaptureQueue(directory: directory).load()
        precondition(reopened.entries.map(\.id) == [entry.id])
        precondition(reopened.entries.first?.capture.text == text && reopened.unreadable == 1)
        if CommandLine.arguments.count > 1 {
            try FileManager.default.copyItem(at: entry.file, to: URL(fileURLWithPath: CommandLine.arguments[1]))
        }
        try queue.remove(entry.id)
        let afterRemoval = try queue.load()
        precondition(afterRemoval.entries.isEmpty && afterRemoval.unreadable == 1)
        print("PASS: offline save, restart, invalid input, corrupt entry isolation and removal")
    }
}
