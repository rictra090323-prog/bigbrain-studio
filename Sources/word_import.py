"""Convert the visible body of a Word document to local Markdown."""
from io import BytesIO
import re
from urllib.parse import quote, urlsplit
from xml.etree import ElementTree as ET
from zipfile import BadZipFile, ZipFile
from zlib import error as DecompressionError

MAX_DOCUMENT = 10_000_000
MAX_XML = 2_000_000
NS = {
    "w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main",
    "r": "http://schemas.openxmlformats.org/officeDocument/2006/relationships",
}
W = "{" + NS["w"] + "}"
R = "{" + NS["r"] + "}"


def literal(text):
    return re.sub(r"([\\`*_[\]<>|#~])", r"\\\1", text)


def read_part(archive, name, required=False):
    try:
        info = archive.getinfo(name)
    except KeyError:
        if required:
            raise ValueError("Word-filen saknar dokumenttext.") from None
        return None
    if info.file_size > MAX_XML:
        raise ValueError("Word-dokumentets innehåll är för stort.")
    with archive.open(info) as file:
        text = file.read(MAX_XML + 1).decode("utf-8-sig")
    if re.search(r"<!\s*(?:DOCTYPE|ENTITY)", text, re.IGNORECASE):
        raise ValueError("Word-dokumentet innehåller en XML-definition som inte stöds.")
    return ET.fromstring(text)


def safe_link(value):
    try:
        parsed = urlsplit(value)
    except ValueError:
        return ""
    if parsed.scheme not in ("https", "http") or not parsed.hostname or parsed.username or parsed.password:
        return ""
    return quote(value, safe=":/?#[]@!$&'()*+,;=%")


def content_children(node, tags):
    for child in node:
        if child.tag in tags:
            yield child
        elif child.tag == W + "sdt":
            content = child.find("w:sdtContent", NS)
            if content is not None:
                yield from content_children(content, tags)


def inline(node, links):
    if node.tag == W + "t":
        return literal(node.text or "")
    if node.tag in (W + "tab", W + "br", W + "cr"):
        return " "
    if node.tag in (W + "del", W + "moveFrom", W + "pPr", W + "rPr", W + "drawing", W + "pict"):
        return ""
    if node.tag == W + "r":
        vanish = node.find("w:rPr/w:vanish", NS)
        if vanish is not None and vanish.get(W + "val") not in ("0", "false", "off"):
            return ""
    if node.tag == W + "sdt":
        content = node.find("w:sdtContent", NS)
        return inline(content, links) if content is not None else ""
    text = "".join(inline(child, links) for child in node)
    link = links.get(node.get(R + "id")) if node.tag == W + "hyperlink" else ""
    return f"[{text}](<{link}>)" if link and text else text


def paragraph(node, links, headings):
    text = inline(node, links).strip()
    if not text:
        return "", None
    level = node.find("w:pPr/w:outlineLvl", NS)
    if level is not None and re.fullmatch(r"[0-8]", level.get(W + "val", "")):
        return "#" * min(6, int(level.get(W + "val")) + 2) + " " + text, None
    style = node.find("w:pPr/w:pStyle", NS)
    if style is not None:
        name = style.get(W + "val", "")
        heading = re.fullmatch(r"(?:heading|rubrik)\s*([1-9])", name, re.IGNORECASE)
        if name in headings or heading:
            depth = headings[name] if name in headings else int(heading[1])
            return "#" * min(6, depth + 1) + " " + text, None
    if node.find("w:pPr/w:numPr/w:numId", NS) is not None:
        level = node.find("w:pPr/w:numPr/w:ilvl", NS)
        depth = level.get(W + "val", "") if level is not None else ""
        return text, int(depth) if re.fullmatch(r"[0-8]", depth) else 0
    if re.match(r"(?:[-+>] |\d+[.)] )", text):
        text = "\\" + text
    return text, None


def table(node, links):
    rows = [
        [" ".join(inline(p, links).strip() for p in content_children(cell, (W + "p",))).strip()
         for cell in content_children(row, (W + "tc",))]
        for row in content_children(node, (W + "tr",)) if row.find("w:trPr/w:del", NS) is None
    ]
    if not rows:
        return ""
    columns = max(map(len, rows))
    if not columns:
        return ""
    if columns > 50 or len(rows) > 5000:
        raise ValueError("Word-dokumentet innehåller en tabell som är för stor.")
    lines = ["| " + " | ".join(row + [""] * (columns - len(row))) + " |" for row in rows]
    lines.insert(1, "| " + " | ".join(["---"] * columns) + " |")
    return "\n".join(lines)


def convert(data):
    try:
        with ZipFile(BytesIO(data)) as archive:
            document = read_part(archive, "word/document.xml", required=True)
            relationships = read_part(archive, "word/_rels/document.xml.rels")
            styles = read_part(archive, "word/styles.xml")
        links = {
            item.get("Id"): safe_link(item.get("Target", ""))
            for item in (relationships if relationships is not None else [])
            if item.get("TargetMode") == "External" and item.get("Type", "").endswith("/hyperlink")
        }
        headings = {}
        if styles is not None:
            for style in styles.findall("w:style", NS):
                level = style.find("w:pPr/w:outlineLvl", NS)
                value = level.get(W + "val", "") if level is not None else ""
                if re.fullmatch(r"[0-8]", value):
                    headings[style.get(W + "styleId")] = int(value) + 1
        body = document.find("w:body", NS)
        if body is None:
            raise ValueError("Word-filen saknar dokumenttext.")
        blocks = []
        previous_depth = None
        for node in content_children(body, (W + "p", W + "tbl")):
            if node.tag == W + "p":
                text, depth = paragraph(node, links, headings)
            else:
                text, depth = table(node, links), None
            if not text:
                continue
            if blocks:
                blocks.append("\n" if previous_depth is not None and depth is not None else "\n\n")
            if depth is not None:
                # Markdown needs a parent item before another indentation level.
                depth = min(depth, previous_depth + 1 if previous_depth is not None else 0)
                text = "  " * depth + "- " + text
            blocks.append(text)
            previous_depth = depth
        if not blocks:
            raise ValueError("Word-filen innehöll ingen text som kan importeras.")
        return "".join(blocks)
    except (BadZipFile, DecompressionError, ET.ParseError, UnicodeError, RecursionError, RuntimeError) as error:
        raise ValueError("Word-filen är skadad, krypterad eller använder ett format som inte stöds.") from error
