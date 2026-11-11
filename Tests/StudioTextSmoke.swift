import AppKit

@main
struct StudioTextSmoke {
    @MainActor
    static func main() {
        let documents = [
            "# Kursanteckning\n\nText med **betoning**, *kursiv* och ***båda***.\n- Äldre lista\n",
            "---\ntitle: Kurs\n---\n# Äldre\n\n| Ämne | Källa |\n| --- | --- |\n[[Länk]]\n",
            "```swift\n# kommentaren\n**stjärnor**\n```\n\nEn rad med emoji 🍓 och å.  \n\n",
            "# Rubrik\n\n[Stöd](<./Fil.md>)\nOrd med \\* och `kod`.\n\n",
            "Två ** markerade ** och **en** slutrad   ",
            "### Fördjupning\n> Ett *citat*\n9. Steg\n- [ ] Läs **sidan** 🍓\n- [x] Anteckna\n- [X] Äldre checklista\n> [Källa](./källa.md)\n",
            "Formatering med <u>understrykning 🍓</u>, ~~genomstrykning~~ och ~~<u>***allt***</u>~~.",
            ""
        ]
        for document in documents {
            let roundtrip = StudioMarkdown.write(StudioMarkdown.read(document))
            precondition(roundtrip == document, "Markdown roundtrip changed an existing document")
        }
        let rich = StudioMarkdown.read(documents[0])
        precondition(rich.string.hasPrefix("Kursanteckning") && !rich.string.contains("**"))
        let marker = (rich.string as NSString).range(of: "betoning")
        precondition(rich.attribute(StudioMarkdown.emphasis, at: marker.location, effectiveRange: nil) as? Int == StudioMarkdown.bold)

        _ = NSApplication.shared
        let editor = StudioTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
        editor.isRichText = true
        editor.textStorage?.setAttributedString(StudioMarkdown.read("Ord om religion 🍓\n\nText\n"))
        let religion = (editor.string as NSString).range(of: "religion")
        editor.setSelectedRange(religion)
        editor.changeEmphasis(StudioMarkdown.bold)
        precondition(StudioMarkdown.write(editor.textStorage!).contains("**religion**"))
        editor.changeEmphasis(StudioMarkdown.italic)
        precondition(StudioMarkdown.write(editor.textStorage!).contains("***religion***"))
        editor.changeParagraph(.heading)
        precondition(StudioMarkdown.write(editor.textStorage!).hasPrefix("# Ord om ***religion***"))
        let combined = (editor.string as NSString).range(of: "religion")
        editor.setSelectedRange(combined)
        editor.changeEmphasis(StudioMarkdown.underline)
        editor.changeEmphasis(StudioMarkdown.strike)
        let saved = StudioMarkdown.write(editor.textStorage!)
        precondition(saved.contains("~~<u>***religion***</u>~~"))
        let reopened = StudioMarkdown.read(saved)
        let reopenedRange = (reopened.string as NSString).range(of: "religion")
        precondition(reopened.attribute(.underlineStyle, at: reopenedRange.location, effectiveRange: nil) as? Int == 1)
        precondition(reopened.attribute(.strikethroughStyle, at: reopenedRange.location, effectiveRange: nil) as? Int == 1)
        let text = (editor.string as NSString).range(of: "Text")
        editor.setSelectedRange(NSRange(location: text.location + 1, length: 0))
        editor.changeParagraph(.list)
        precondition(StudioMarkdown.write(editor.textStorage!).contains("\n- Text\n"))
        editor.setSelectedRange(NSRange(location: (editor.string as NSString).range(of: "Text").upperBound, length: 0))
        editor.insertNewline(nil)
        editor.insertText("Ny rad", replacementRange: editor.selectedRange())
        precondition(StudioMarkdown.write(editor.textStorage!).contains("- Text\n- Ny rad"))
        editor.textStorage?.setAttributedString(StudioMarkdown.read("### Avsnitt\n> Citat\n9. Steg\n- [ ] Uppgift 🍓"))
        let extended = editor.textStorage!
        precondition(extended.string == "Avsnitt\nCitat\n9. Steg\n☐ Uppgift 🍓")
        editor.setSelectedRange(NSRange(location: (editor.string as NSString).range(of: "Steg").upperBound, length: 0))
        editor.insertNewline(nil)
        editor.insertText("Fortsättning", replacementRange: editor.selectedRange())
        precondition(StudioMarkdown.write(extended).contains("9. Steg\n10. Fortsättning"))
        editor.setSelectedRange(NSRange(location: extended.length, length: 0))
        editor.toggleChecklist()
        precondition(StudioMarkdown.write(extended).hasSuffix("- [x] Uppgift 🍓"))
        editor.insertNewline(nil)
        precondition(StudioMarkdown.write(extended).hasSuffix("- [x] Uppgift 🍓\n- [ ] "))
        editor.insertNewline(nil)
        precondition(StudioMarkdown.write(extended).hasSuffix("- [x] Uppgift 🍓\n"))
        editor.insertText("Reflektion", replacementRange: editor.selectedRange())
        editor.changeParagraph(.quote)
        precondition(StudioMarkdown.write(extended).hasSuffix("> Reflektion"))
        let revision = String(repeating: "a", count: 64)
        let citation = StudioCitation(markup: "[Källa 🍓](<../K%C3%A4llor/Original.md> \"BigBrain:\(revision):13:42\")")!
        let referenceText = "Ett **påstående** " + citation.markup + "."
        let formattedCitation = StudioMarkdown.read(referenceText)
        precondition(formattedCitation.string == "Ett påstående Källa 🍓.")
        precondition(StudioMarkdown.write(formattedCitation) == referenceText)
        let citationLocation = (formattedCitation.string as NSString).range(of: citation.title).location
        precondition(formattedCitation.attribute(StudioCitation.attribute, at: citationLocation, effectiveRange: nil)
                     as? String == citation.markup)
        editor.textStorage?.setAttributedString(StudioMarkdown.read("Ett påstående."))
        editor.insertCitation(citation, at: ("Ett påstående" as NSString).length)
        precondition(StudioMarkdown.write(editor.textStorage!) == "Ett påstående " + citation.markup + ".")
        editor.changeParagraph(.quote)
        precondition(StudioMarkdown.write(editor.textStorage!) == "> Ett påstående " + citation.markup + ".")
        editor.textStorage?.setAttributedString(StudioMarkdown.read("En mening."))
        editor.insertCitation(citation, at: ("En mening." as NSString).length)
        precondition(StudioMarkdown.write(editor.textStorage!) == "En mening. " + citation.markup)
        editor.textStorage?.setAttributedString(StudioMarkdown.read("Text\n\n## Rubrik"))
        editor.insertCitation(citation, at: ("Text\n\n" as NSString).length)
        precondition(StudioMarkdown.write(editor.textStorage!) == "Text\n\n## " + citation.markup + " Rubrik")
        print("PASS: Markdown roundtrip, rich styles, UTF-16 selections, lists, checklists and citation insertion")
    }
}
