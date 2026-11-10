import AppKit
import CoreText
import UniformTypeIdentifiers

enum StudioExport: String, CaseIterable {
    case pdf, docx, md

    var label: String {
        switch self {
        case .pdf: "PDF"
        case .docx: "Word"
        case .md: "Markdown"
        }
    }

    var icon: String {
        switch self {
        case .pdf: "doc.richtext"
        case .docx: "doc.text"
        case .md: "number"
        }
    }

    @MainActor
    func save(markdown: String, title: String, in window: NSWindow?, onFailure: @escaping (String) -> Void) {
        let panel = NSSavePanel()
        panel.title = "Exportera till " + label
        panel.prompt = "Exportera"
        panel.nameFieldStringValue = title.replacingOccurrences(of: "/", with: "-") + "." + rawValue
        panel.allowedContentTypes = [UTType(filenameExtension: rawValue) ?? .data]
        let complete: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try data(markdown: markdown, title: title).write(to: url, options: .atomic)
            } catch {
                onFailure(error.localizedDescription)
            }
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: complete)
        } else {
            complete(panel.runModal())
        }
    }

    @MainActor
    func data(markdown: String, title: String) throws -> Data {
        if self == .md { return Data(markdown.utf8) }
        let text = NSMutableAttributedString(attributedString: StudioMarkdown.read(markdown))
        let range = NSRange(location: 0, length: text.length)
        text.addAttribute(.foregroundColor, value: NSColor.black, range: range)
        if self == .docx {
            return try text.data(from: range, documentAttributes: [
                .documentType: NSAttributedString.DocumentType.officeOpenXML,
                .title: title
            ])
        }
        return try Self.pdf(text, title: title)
    }

    private static func pdf(_ text: NSAttributedString, title: String) throws -> Data {
        let output = NSMutableData()
        var page = CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
        guard let consumer = CGDataConsumer(data: output as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &page, [kCGPDFContextTitle: title] as CFDictionary) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let framesetter = CTFramesetterCreateWithAttributedString(text)
        let body = CGPath(rect: page.insetBy(dx: 54, dy: 54), transform: nil)
        var offset = 0
        repeat {
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: offset, length: 0), body, nil)
            let visible = CTFrameGetVisibleStringRange(frame)
            guard visible.length > 0 || text.length == 0 else { throw CocoaError(.fileWriteUnknown) }
            context.beginPDFPage(nil)
            context.textMatrix = .identity
            CTFrameDraw(frame, context)
            context.endPDFPage()
            offset += visible.length
        } while offset < text.length
        context.closePDF()
        return output as Data
    }
}
