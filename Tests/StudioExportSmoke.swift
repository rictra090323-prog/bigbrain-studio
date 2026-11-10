import AppKit
import PDFKit

@main
struct StudioExportSmoke {
    @MainActor
    static func main() throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let source = "### Studieanteckning\n\n- [x] **Läs** kapitlet.\n- [ ] Skriv svar.\n\n> Källa med åäö.\n\n"
            + (1...180).map { "Stycke \($0) om skogen och östersjön." }.joined(separator: "\n\n")
            + "\n\nSista raden är också med 🍓.\n"
        for format in StudioExport.allCases {
            let file = directory.appendingPathComponent("Studieanteckning." + format.rawValue)
            let data = try format.data(markdown: source, title: "Studieanteckning")
            try data.write(to: file)
            switch format {
            case .md:
                precondition(String(data: data, encoding: .utf8) == source)
            case .docx:
                let word = try NSAttributedString(data: data, options: [
                    .documentType: NSAttributedString.DocumentType.officeOpenXML
                ], documentAttributes: nil)
                precondition(word.string.contains("☑ Läs kapitlet."))
                precondition(word.string.contains("Sista raden är också med 🍓."))
                let title = (word.string as NSString).range(of: "Studieanteckning")
                let font = word.attribute(.font, at: title.location, effectiveRange: nil) as? NSFont
                precondition(font?.pointSize == 18)
            case .pdf:
                guard let pdf = PDFDocument(data: data) else { preconditionFailure("Invalid PDF") }
                precondition(pdf.pageCount > 1)
                let allText = (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined(separator: "\n")
                precondition(allText.contains("Sista raden är också med"))
                for n in 1...180 {
                    precondition(allText.contains("Stycke \(n) om skogen"), "Missing paragraph \(n)")
                }
            }
        }
        print("PASS: exact Markdown, formatted Word, and complete multi-page PDF")
    }
}
