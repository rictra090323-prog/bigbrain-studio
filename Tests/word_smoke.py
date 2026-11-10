"""Exercise Word import and search with a synthetic document and disposable library."""
from io import BytesIO
import json
import os
from pathlib import Path
from struct import unpack_from
import subprocess
import sys
import tempfile
from zipfile import ZIP_DEFLATED, ZipFile

bridge = Path(sys.argv[1]).resolve()
document = """<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <w:body>
    <w:p><w:pPr><w:pStyle w:val="ProjectHeading"/></w:pPr><w:r><w:t>Plan för vårterminen</w:t></w:r></w:p>
    <w:p><w:r><w:t>Projektbeslutet heter björkskugga.</w:t></w:r></w:p>
    <w:p><w:r><w:rPr><w:vanish/></w:rPr><w:t>Förtroendeanteckning</w:t></w:r></w:p>
    <w:p><w:r><w:rPr><w:vanish w:val="0"/></w:rPr><w:t>Synlig rättelse</w:t></w:r></w:p>
    <w:sdt><w:sdtPr/><w:sdtContent><w:p><w:r><w:t>Studieplan i innehållskontroll</w:t></w:r></w:p></w:sdtContent></w:sdt>
    <w:p><w:pPr><w:numPr><w:numId w:val="1"/></w:numPr></w:pPr><w:r><w:t>Kontrollera schemat</w:t></w:r></w:p>
    <w:p><w:pPr><w:numPr><w:ilvl w:val="1"/><w:numId w:val="1"/></w:numPr></w:pPr><w:r><w:t>Stäm av tider</w:t></w:r></w:p>
    <w:p><w:hyperlink r:id="rId1"><w:r><w:t>Kurskällan</w:t></w:r></w:hyperlink></w:p>
    <w:p><w:hyperlink r:id="rId2"><w:r><w:t>Osäkert mål</w:t></w:r></w:hyperlink></w:p>
    <w:p><w:del><w:r><w:delText>Borttagen text</w:delText></w:r></w:del></w:p>
    <w:tbl>
      <w:tr><w:tc><w:p><w:r><w:t>Vecka</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>Uppgift</w:t></w:r></w:p></w:tc></w:tr>
      <w:tr><w:tc><w:p><w:r><w:t>12</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>Seminarium</w:t></w:r></w:p></w:tc></w:tr>
      <w:tr><w:trPr><w:del w:id="1"/></w:trPr><w:tc><w:p><w:r><w:t>Raderad tabellrad</w:t></w:r></w:p></w:tc></w:tr>
    </w:tbl>
  </w:body>
</w:document>"""
styles = """<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
<w:style w:type="paragraph" w:styleId="ProjectHeading"><w:pPr><w:outlineLvl w:val="0"/></w:pPr></w:style>
</w:styles>"""
relationships = """<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink"
 TargetMode="External" Target="https://example.org/course"/>
<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink"
 TargetMode="External" Target="file:///secret.md"/>
</Relationships>"""


def docx(body):
    buffer = BytesIO()
    with ZipFile(buffer, "w", ZIP_DEFLATED) as archive:
        archive.writestr("word/document.xml", body)
        archive.writestr("word/styles.xml", styles)
        archive.writestr("word/_rels/document.xml.rels", relationships)
    return buffer.getvalue()


with tempfile.TemporaryDirectory(prefix="bigbrain-word-") as tmp:
    root = Path(tmp).resolve()
    vault = root / "vault"
    (vault / ".obsidian").mkdir(parents=True)
    env = dict(os.environ, BIGBRAIN_AGENT_HOME=str(root / "agent"), BIGBRAIN_VAULT=str(vault),
               CODEX_HOME=str(root / "codex"))

    def run(*args, data=b"", fail=False):
        result = subprocess.run([str(bridge), *args], input=data, capture_output=True, env=env, timeout=30)
        assert (result.returncode != 0) == fail, (args, result.stdout, result.stderr)
        return json.loads(result.stdout)

    filename = "-Projektanteckningar.docx"
    file = docx(document)
    imported = run("import-word", "--", filename, data=file)
    note = imported["note"]
    assert imported["created"] and note["path"].startswith("Importerade/Word/")
    for expected in ("## Plan för vårterminen", "Synlig rättelse", "Studieplan i innehållskontroll",
                     "- Kontrollera schemat\n  - Stäm av tider",
                     "[Kurskällan](<https://example.org/course>)", "| 12 | Seminarium |", filename):
        assert expected in note["body"], (expected, note["body"])
    assert "Borttagen text" not in note["body"] and "file:///" not in note["body"]
    assert "Förtroendeanteckning" not in note["body"]
    assert not run("search", "förtroendeanteckning", "--fast", "--scope", "note")
    assert "Raderad tabellrad" not in note["body"]
    hits = run("search", "björkskugga", "--fast", "--scope", "note")
    assert hits[0]["path"] == note["path"]

    edited = note["body"] + "\nKontrollerat av användaren.\n"
    run("save-note", note["path"], note["revision"], "-", data=edited.encode())
    again = run("import-word", "Samma innehåll.docx", data=file)
    assert not again["created"] and again["note"]["path"] == note["path"]
    assert again["note"]["body"] == edited

    assert "formatet .docx" in run("import-word", "Anteckningar.doc", data=file, fail=True)["error"]
    assert "skadad" in run("import-word", "Trasig.docx", data=b"broken", fail=True)["error"]
    corrupt = bytearray(file)
    with ZipFile(BytesIO(corrupt)) as archive:
        offset = archive.getinfo("word/document.xml").header_offset
    name_size, extra_size = unpack_from("<HH", corrupt, offset + 26)
    corrupt[offset + 30 + name_size + extra_size] = 6  # Reserved DEFLATE block type.
    assert "skadad" in run("import-word", "Trasig XML.docx", data=corrupt, fail=True)["error"]
    hostile = docx('<!DOCTYPE word [<!ENTITY secret SYSTEM "file:///private/test">]>' + document)
    assert "XML-definition" in run("import-word", "XML.docx", data=hostile, fail=True)["error"]
    oversized = docx(document + " " * 2_000_001)
    assert "för stort" in run("import-word", "Stor.docx", data=oversized, fail=True)["error"]
    assert list((vault / "Importerade/Word").glob("*.md")) == [Path(note["file"])]

    Path(note["file"]).unlink()
    run("index")
    assert not run("search", "björkskugga", "--fast", "--scope", "note")
    print("PASS: Word structure, hidden and deleted text, safe links, search, edit, repeat import, invalid files and index removal")
