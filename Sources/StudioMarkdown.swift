import AppKit

enum StudioParagraph: String, CaseIterable {
    case text = "Text"
    case heading = "Rubrik 1", subheading = "Rubrik 2", smallHeading = "Rubrik 3"
    case list = "Punktlista", numbered = "Numrerad lista", checklist = "Checklista"
    case quote = "Citat"

    private static let ordered = try! NSRegularExpression(pattern: #"^[0-9]{1,9}\. "#)

    var prefix: String {
        switch self {
        case .text, .list, .numbered, .checklist: ""
        case .heading: "# "
        case .subheading: "## "
        case .smallHeading: "### "
        case .quote: "> "
        }
    }

    var firstItem: String {
        switch self {
        case .list: "- "
        case .numbered: "1. "
        case .checklist: "☐ "
        default: ""
        }
    }

    func itemMarker(in line: String) -> String? {
        switch self {
        case .list: return line.hasPrefix("- ") ? "- " : nil
        case .checklist: return ["☐ ", "☑ "].first(where: line.hasPrefix)
        case .numbered:
            let value = line as NSString
            guard let match = Self.ordered.firstMatch(in: line, range: NSRange(location: 0, length: value.length)) else { return nil }
            return value.substring(with: match.range)
        default: return nil
        }
    }

    func nextItem(after marker: String) -> String {
        if self == .numbered, let number = Int(marker.dropLast(2)), number < 999_999_999 {
            return "\(number + 1). "
        }
        return firstItem
    }
}

struct StudioCitation: Equatable {
    static let attribute = NSAttributedString.Key("BigBrainCitation")
    static let pattern = try! NSRegularExpression(
        pattern: #"\[([^\[\]\n]+)\]\(<([^<>\s]+)> "BigBrain:([a-f0-9]{64}):([0-9]+):([0-9]+)"\)"#)
    let markup: String
    let title: String
    let relativePath: String
    let revision: String
    let start: Int
    let length: Int

    init?(markup: String) {
        let string = markup as NSString
        let entire = NSRange(location: 0, length: string.length)
        guard let match = Self.pattern.firstMatch(in: markup, range: entire), match.range == entire,
              let start = Int(string.substring(with: match.range(at: 4))),
              let length = Int(string.substring(with: match.range(at: 5))),
              length > 0 else { return nil }
        let path = string.substring(with: match.range(at: 2))
        guard path.hasPrefix("./") || path.hasPrefix("../") else { return nil }
        self.markup = markup
        title = string.substring(with: match.range(at: 1))
        relativePath = path
        revision = string.substring(with: match.range(at: 3))
        self.start = start
        self.length = length
    }

    func attributed(paragraph: StudioParagraph) -> NSAttributedString {
        var attributes = StudioMarkdown.style(paragraph)
        attributes[Self.attribute] = markup
        attributes[.link] = relativePath
        return NSAttributedString(string: title, attributes: attributes)
    }
}

enum StudioMarkdown {
    static let block = NSAttributedString.Key("BigBrainParagraph")
    static let emphasis = NSAttributedString.Key("BigBrainEmphasis")
    static let bold = 1, italic = 2, underline = 4, strike = 8
    private static let spans = try! NSRegularExpression(pattern: #"(?<!\*)(\*{1,3})([^*]+?)\1(?!\*)|<u>([^<>]+)</u>|(?<!~)~~([^~]+)~~(?!~)"#)

    static func style(_ paragraph: StudioParagraph = .text, _ marks: Int = 0) -> [NSAttributedString.Key: Any] {
        let size: CGFloat = switch paragraph {
        case .heading: 26
        case .subheading: 21
        case .smallHeading: 18
        default: 16
        }
        let baseFont = NSFont.systemFont(ofSize: size, weight: size > 16 || marks & bold != 0 ? .semibold : .regular)
        let font = marks & italic == 0 ? baseFont : NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
        let layout = NSMutableParagraphStyle()
        layout.lineSpacing = 4
        layout.paragraphSpacing = 5
        if !paragraph.firstItem.isEmpty {
            layout.firstLineHeadIndent = 14
            layout.headIndent = paragraph == .numbered ? 36 : 30
        } else if paragraph == .quote {
            layout.firstLineHeadIndent = 18
            layout.headIndent = 18
        }
        return [.font: font, .foregroundColor: paragraph == .quote ? NSColor.secondaryLabelColor : NSColor.labelColor,
                .paragraphStyle: layout, .underlineStyle: marks & underline == 0 ? 0 : NSUnderlineStyle.single.rawValue,
                .strikethroughStyle: marks & strike == 0 ? 0 : NSUnderlineStyle.single.rawValue,
                block: paragraph.rawValue, emphasis: marks]
    }

    static func paragraph(_ value: Any?) -> StudioParagraph {
        (value as? String).flatMap(StudioParagraph.init(rawValue:)) ?? .text
    }

    static func read(_ source: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var fence: String?
        var frontMatter = false
        for (index, line) in source.components(separatedBy: "\n").enumerated() {
            if index > 0 { result.append(NSAttributedString(string: "\n", attributes: style())) }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let marker = ["```", "~~~"].first { trimmed.hasPrefix($0) }
            if (index == 0 && trimmed == "---") || (frontMatter && trimmed == "---") { frontMatter.toggle() }
            let taskMarker = ["- [ ] ", "- [x] "].first(where: line.hasPrefix)
            let inlineSource = taskMarker.map { line.dropFirst($0.count) } ?? line.dropFirst(line.hasPrefix("> ") ? 2 : 0)
            let inlineMarkup = inlineSource.replacingOccurrences(of: "<u>", with: "").replacingOccurrences(of: "</u>", with: "")
            let markup = StudioCitation.pattern.stringByReplacingMatches(in: inlineMarkup,
                range: NSRange(location: 0, length: (inlineMarkup as NSString).length), withTemplate: "")
            let code = frontMatter || fence != nil || marker != nil
            let literal = code || markup.contains { "[]<>_|`\\".contains($0) }
            if let marker, fence == nil { fence = marker }
            else if marker == fence && marker != nil { fence = nil }
            let kind: StudioParagraph
            let content: String
            if literal {
                kind = .text
                content = line
            } else if let taskMarker {
                kind = .checklist
                content = (taskMarker == "- [x] " ? "☑ " : "☐ ") + String(inlineSource)
            } else {
                kind = StudioParagraph.allCases.first {
                    (!$0.prefix.isEmpty && line.hasPrefix($0.prefix) && line.count > $0.prefix.count)
                        || ($0 != .checklist && $0.itemMarker(in: line) != nil)
                } ?? .text
                content = String(line.dropFirst(kind.prefix.count))
            }
            if code {
                result.append(NSAttributedString(string: content, attributes: style(kind)))
            } else {
                appendCitations(content, paragraph: kind, literal: literal, to: result)
            }
        }
        return write(result) == source ? result : NSAttributedString(string: source, attributes: style())
    }

    private static func appendCitations(_ content: String, paragraph: StudioParagraph, literal: Bool,
                                        to result: NSMutableAttributedString) {
        let string = content as NSString
        var start = 0
        func appendText(_ text: String) {
            if literal {
                result.append(NSAttributedString(string: text, attributes: style(paragraph)))
            } else {
                appendInline(text, paragraph: paragraph, to: result)
            }
        }
        for match in StudioCitation.pattern.matches(in: content, range: NSRange(location: 0, length: string.length)) {
            guard let citation = StudioCitation(markup: string.substring(with: match.range)) else { continue }
            appendText(string.substring(with: NSRange(location: start, length: match.range.location - start)))
            result.append(citation.attributed(paragraph: paragraph))
            start = NSMaxRange(match.range)
        }
        appendText(string.substring(from: start))
    }

    private static func appendInline(_ content: String, paragraph: StudioParagraph, marks: Int = 0,
                                     to result: NSMutableAttributedString) {
        let string = content as NSString
        var start = 0
        for match in spans.matches(in: content, range: NSRange(location: 0, length: string.length)) {
            let plain = NSRange(location: start, length: match.range.location - start)
            result.append(NSAttributedString(string: string.substring(with: plain), attributes: style(paragraph, marks)))
            if match.range(at: 1).location != NSNotFound {
                let length = match.range(at: 1).length
                let extra = length == 3 ? bold | italic : length == 2 ? bold : italic
                appendInline(string.substring(with: match.range(at: 2)), paragraph: paragraph, marks: marks | extra, to: result)
            } else if match.range(at: 3).location != NSNotFound {
                appendInline(string.substring(with: match.range(at: 3)), paragraph: paragraph, marks: marks | underline, to: result)
            } else {
                appendInline(string.substring(with: match.range(at: 4)), paragraph: paragraph, marks: marks | strike, to: result)
            }
            start = NSMaxRange(match.range)
        }
        result.append(NSAttributedString(string: string.substring(from: start), attributes: style(paragraph, marks)))
    }

    static func write(_ text: NSAttributedString) -> String {
        var offset = 0
        let whole = text.string as NSString
        return text.string.components(separatedBy: "\n").map { line in
            let length = (line as NSString).length
            defer { offset += length + 1 }
            guard length > 0 else { return "" }
            let kind = paragraph(text.attribute(block, at: offset, effectiveRange: nil))
            let marker = kind.itemMarker(in: line) ?? ""
            let markerLength = (marker as NSString).length
            var result = kind.prefix + marker
            if kind == .checklist && !marker.isEmpty { result = marker == "☑ " ? "- [x] " : "- [ ] " }
            let contentRange = NSRange(location: offset + markerLength, length: length - markerLength)
            text.enumerateAttribute(StudioCitation.attribute, in: contentRange) { value, citationRange, _ in
                if let markup = value as? String, let citation = StudioCitation(markup: markup),
                   whole.substring(with: citationRange) == citation.title {
                    result += markup
                    return
                }
                text.enumerateAttribute(emphasis, in: citationRange) { value, range, _ in
                    let content = whole.substring(with: range)
                    let marks = value as? Int ?? 0
                    let stars = String(repeating: "*", count: (marks & bold == 0 ? 0 : 2) + (marks & italic == 0 ? 0 : 1))
                    let u = marks & underline == 0 ? "" : "<u>"
                    let endU = marks & underline == 0 ? "" : "</u>"
                    let strike = marks & Self.strike == 0 ? "" : "~~"
                    let trimmed = content.trimmingCharacters(in: .whitespaces)
                    guard marks != 0, !trimmed.isEmpty, let inner = content.range(of: trimmed) else {
                        result += content
                        return
                    }
                    result += content[..<inner.lowerBound] + strike + u + stars + trimmed + stars + endU + strike + content[inner.upperBound...]
                }
            }
            return result
        }.joined(separator: "\n")
    }
}

final class StudioTextView: NSTextView {
    var markdownMode = false

    override func paste(_ sender: Any?) { pasteAsPlainText(sender) }

    override func insertNewline(_ sender: Any?) {
        guard !markdownMode, !hasMarkedText() else { super.insertNewline(sender); return }
        let kind = currentParagraph
        let line = paragraphText
        let list = kind.itemMarker(in: line) != nil ? kind : line.hasPrefix("- ") ? .list : .text
        let marker = list.itemMarker(in: line)
        if let marker, line == marker, selectedRange().length == 0 {
            changeParagraph(.text)
            return
        }
        super.insertNewline(sender)
        typingAttributes = StudioMarkdown.style(list)
        if let marker { insertText(list.nextItem(after: marker), replacementRange: selectedRange()) }
    }

    private var currentParagraph: StudioParagraph {
        guard let storage = textStorage, lineRange.location < storage.length else { return .text }
        return StudioMarkdown.paragraph(storage.attribute(StudioMarkdown.block, at: lineRange.location, effectiveRange: nil))
    }

    private var lineRange: NSRange {
        let text = string as NSString
        let caret = min(selectedRange().location, text.length)
        return text.lineRange(for: NSRange(location: caret, length: 0))
    }

    var paragraphText: String {
        (string as NSString).substring(with: lineRange).trimmingCharacters(in: .newlines)
    }

    var lookupText: String {
        let range = selectedRange()
        return range.length > 0 ? (string as NSString).substring(with: range) : paragraphText
    }

    func changeParagraph(_ kind: StudioParagraph) {
        guard !markdownMode, let storage = textStorage else { return }
        var range = lineRange
        if (storage.string as NSString).substring(with: range).hasSuffix("\n") { range.length -= 1 }
        let replacement = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))
        let previousKind = currentParagraph
        let oldMarker = previousKind.itemMarker(in: replacement.string) ?? StudioParagraph.list.itemMarker(in: replacement.string) ?? ""
        let newMarker = previousKind == kind && !oldMarker.isEmpty ? oldMarker : kind.firstItem
        replacement.replaceCharacters(in: NSRange(location: 0, length: (oldMarker as NSString).length),
                                      with: NSAttributedString(string: newMarker, attributes: StudioMarkdown.style(kind)))
        let formatted = NSRange(location: 0, length: replacement.length)
        replacement.enumerateAttributes(in: formatted) { attributes, span, _ in
            var style = StudioMarkdown.style(kind, attributes[StudioMarkdown.emphasis] as? Int ?? 0)
            style[StudioCitation.attribute] = attributes[StudioCitation.attribute]
            style[.link] = attributes[.link]
            replacement.setAttributes(style, range: span)
        }
        let next = NSMutableAttributedString(attributedString: storage)
        next.replaceCharacters(in: range, with: replacement)
        let markerChange = (newMarker as NSString).length - (oldMarker as NSString).length
        let caret = max(range.location, min(selectedRange().location + markerChange, range.location + replacement.length))
        replace(next, selection: NSRange(location: caret, length: 0))
        typingAttributes = StudioMarkdown.style(kind)
        window?.makeFirstResponder(self)
    }

    func toggleChecklist() {
        guard !markdownMode, currentParagraph == .checklist, let storage = textStorage,
              let marker = StudioParagraph.checklist.itemMarker(in: paragraphText) else { return }
        let checked = marker == "☐ "
        let next = NSMutableAttributedString(attributedString: storage)
        let range = NSRange(location: lineRange.location, length: 1)
        next.replaceCharacters(in: range, with: checked ? "☑" : "☐")
        replace(next, selection: selectedRange())
        window?.makeFirstResponder(self)
    }

    func changeEmphasis(_ flag: Int) {
        guard !markdownMode, let storage = textStorage else { return }
        let range = selectedRange()
        if range.length == 0 {
            let current = typingAttributes[StudioMarkdown.emphasis] as? Int ?? 0
            typingAttributes = StudioMarkdown.style(StudioMarkdown.paragraph(typingAttributes[StudioMarkdown.block]), current ^ flag)
        } else {
            let next = NSMutableAttributedString(attributedString: storage)
            var allMarked = true
            storage.enumerateAttribute(StudioMarkdown.emphasis, in: range) { value, _, _ in
                allMarked = allMarked && ((value as? Int ?? 0) & flag != 0)
            }
            storage.enumerateAttributes(in: range) { attributes, part, _ in
                guard attributes[StudioCitation.attribute] == nil else { return }
                let kind = StudioMarkdown.paragraph(attributes[StudioMarkdown.block])
                let marks = attributes[StudioMarkdown.emphasis] as? Int ?? 0
                next.setAttributes(StudioMarkdown.style(kind, allMarked ? marks & ~flag : marks | flag), range: part)
            }
            replace(next, selection: range)
        }
        window?.makeFirstResponder(self)
    }

    func insertCitation(_ citation: StudioCitation, at offset: Int) {
        guard let storage = textStorage, (0...storage.length).contains(offset) else { return }
        let selection = NSRange(location: offset, length: 0)
        let value = storage.string as NSString
        let leading = offset > 0 && needsSpace(nextTo: value.character(at: offset - 1), punctuation: "([") ? " " : ""
        let trailing = offset < storage.length && needsSpace(nextTo: value.character(at: offset), punctuation: ",.;:!?)]") ? " " : ""
        if markdownMode {
            insertText(leading + citation.markup + trailing, replacementRange: selection)
            return
        }
        let lineStart = value.lineRange(for: selection).location
        let paragraph = lineStart < storage.length
            ? StudioMarkdown.paragraph(storage.attribute(StudioMarkdown.block, at: lineStart, effectiveRange: nil))
            : .text
        let style = StudioMarkdown.style(paragraph)
        let replacement = NSMutableAttributedString(string: leading, attributes: style)
        replacement.append(citation.attributed(paragraph: paragraph))
        replacement.append(NSAttributedString(string: trailing, attributes: style))
        let next = NSMutableAttributedString(attributedString: storage)
        next.replaceCharacters(in: selection, with: replacement)
        replace(next, selection: NSRange(location: offset + replacement.length, length: 0))
        typingAttributes = style
    }

    private func needsSpace(nextTo codeUnit: UInt16, punctuation: String) -> Bool {
        guard let scalar = Unicode.Scalar(codeUnit) else { return true }
        return !CharacterSet.whitespacesAndNewlines.contains(scalar) && !punctuation.unicodeScalars.contains(scalar)
    }

    private func replace(_ next: NSAttributedString, selection: NSRange) {
        guard let storage = textStorage else { return }
        let previous = NSAttributedString(attributedString: storage)
        let previousSelection = selectedRange()
        undoManager?.registerUndo(withTarget: self) { view in view.replace(previous, selection: previousSelection) }
        storage.setAttributedString(next)
        setSelectedRange(selection)
        didChangeText()
    }
}

