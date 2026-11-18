#!/usr/bin/env python3
"""Validate checked-in DOCX RTL specifications using only the standard library.

Checks include DOCX ZIP/XML integrity, source-to-DOCX content, navigation,
embedded architecture graphics, required chapters, and every public RTL port
name/direction/width. It does not replace an engineering or layout review.
"""
from collections import Counter
import hashlib
from pathlib import Path
import re
import struct
import unittest
import zipfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
SPEC_DIR = ROOT / "docs" / "specs"
SOURCE_DIR = SPEC_DIR / "src"
NS = {
    "w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main",
    "a": "http://schemas.openxmlformats.org/drawingml/2006/main",
    "r": "http://schemas.openxmlformats.org/officeDocument/2006/relationships",
}
W = "{" + NS["w"] + "}"
BASELINE = "938ac3409dbcf2c2bc4244f4b3d60f1b19da0c4c"
DOCUMENTS = {
    "aes_core_spec": ("rtl/mdm_aes128.v", "mdm_aes128"),
    "snow3g_core_spec": ("rtl/mdm_snow3g.v", "mdm_snow3g"),
    "zuc_core_spec": ("rtl/mdm_zuc.v", "mdm_zuc"),
    "mdm_sec_spec": ("rtl/mdm_sec.v", "mdm_sec"),
}
REQUIRED_HEADINGS = (
    "1 Introduction",
    "1.1 Purpose",
    "1.2 Scope",
    "1.3 Defines, Symbols, and Abbreviations",
    "1.4 Design Features",
    "1.5 References",
    "2 Microarchitecture",
    "2.1 Background (Algorithm Principle)",
    "2.2 Microarchitecture Analysis",
    "2.2.1 Top Level Diagram",
    "2.2.2 Timing Requirement",
    "2.2.3 Peripheral Interface",
    "2.2.4 Sub-modules",
    "2.2.5 Pipeline Design",
    "3 I/O Interface",
    "4 Open Issue",
)


def text_of(element):
    return "".join(node.text or "" for node in element.iter(W + "t")).strip()


def row_cells(line):
    """Read one Markdown table row, keeping pipes in inline code and ||."""
    text = line.strip()[1:-1]
    cells, current = [], []
    in_code = False
    pos = 0
    while pos < len(text):
        c = text[pos]
        if c == "`":
            in_code = not in_code
            current.append(c)
        elif c == "\\" and pos + 1 < len(text) and text[pos + 1] == "|":
            current.append("|")
            pos += 1
        elif c == "|" and not in_code:
            if pos + 1 < len(text) and text[pos + 1] == "|":
                current.extend(("|", "|"))
                pos += 1
            else:
                cells.append("".join(current).strip())
                current = []
        else:
            current.append(c)
        pos += 1
    if in_code:
        raise AssertionError("Unclosed Markdown inline code: " + line)
    cells.append("".join(current).strip())
    return cells


def unmark(text):
    return text.replace("**", "").replace("`", "").strip()


def expected_paragraphs(source):
    """List all substantive source paragraphs/cells after simple markup removal."""
    paragraphs = []
    in_code = False
    for raw in source.splitlines():
        line = raw.strip()
        if line.startswith("```"):
            in_code = not in_code
            continue
        if not line or re.fullmatch(r"\[\[DIAGRAM:\w+\]\]", line):
            continue
        if in_code:
            paragraphs.append(line)
        elif line.startswith("|"):
            cells = row_cells(line)
            if all(re.fullmatch(r":?-{3,}:?", cell.replace(" ", "")) for cell in cells):
                continue
            paragraphs.extend(unmark(cell) for cell in cells if cell)
        else:
            line = re.sub(r"^#{1,4}\s+", "", line)
            line = re.sub(r"^-\s+", "• ", line)
            paragraphs.append(unmark(line))
    if in_code:
        raise AssertionError("Unclosed Markdown code block")
    return Counter(paragraphs)


def rtl_ports(path):
    """Read the repository's ANSI-style Verilog port declarations."""
    header = path.read_text(encoding="utf-8").split(");", 1)[0]
    pattern = re.compile(
        r"^\s*(input|output)\s+(?:wire|reg)\s+"
        r"(?:\[(\d+)\s*:\s*(\d+)\]\s*)?(\w+)\s*,?\s*$", re.MULTILINE
    )
    result = {}
    for direction, msb, lsb, name in pattern.findall(header):
        width = abs(int(msb) - int(lsb)) + 1 if msb else 1
        result[name] = (direction, width)
    if not result:
        raise AssertionError("No RTL ports parsed: " + str(path))
    return result


def docx_ports(body):
    ports = {}
    for table in body.findall(".//w:tbl", NS):
        rows = table.findall("./w:tr", NS)
        if not rows:
            continue
        header = [text_of(cell) for cell in rows[0].findall("./w:tc", NS)]
        if header != ["信号", "方向", "位宽", "描述"]:
            continue
        for row in rows[1:]:
            cells = [text_of(cell) for cell in row.findall("./w:tc", NS)]
            if len(cells) != 4:
                raise AssertionError("Unexpected port table row: " + repr(cells))
            name, direction, width, _ = cells
            if name in ports:
                raise AssertionError("Duplicate documented port: " + name)
            direction = {"输入": "input", "输出": "output"}.get(direction, direction)
            ports[name] = (direction, int(width))
    return ports


class RtlDesignSpecsTest(unittest.TestCase):
    def test_documents(self):
        for stem, (rtl_path, module) in DOCUMENTS.items():
            with self.subTest(document=stem):
                source_path = SOURCE_DIR / (stem + ".md")
                source_bytes = source_path.read_bytes()
                source = source_bytes.decode("utf-8")
                path = SPEC_DIR / (stem + ".docx")
                with zipfile.ZipFile(path) as archive:
                    self.assertIsNone(archive.testzip(), "Corrupt DOCX ZIP entry")
                    names = archive.namelist()
                    self.assertIn("[Content_Types].xml", names)
                    self.assertIn("word/document.xml", names)
                    self.assertIn("word/styles.xml", names)
                    for entry in names:
                        if entry.endswith((".xml", ".rels")):
                            ET.fromstring(archive.read(entry))
                    body = ET.fromstring(archive.read("word/document.xml"))
                    media = [n for n in names if n.startswith("word/media/")]
                    self.assertEqual(len(media), 1, "Expected one architecture figure")
                    image = archive.read(media[0])
                    self.assertEqual(image[:8], b"\x89PNG\r\n\x1a\n")
                    width, height = struct.unpack(">II", image[16:24])
                    self.assertGreaterEqual(width, 1000)
                    self.assertGreaterEqual(height, 500)
                    self.assertEqual(len(body.findall(".//w:drawing", NS)), 1)
                    blip = body.find(".//a:blip", NS)
                    self.assertIsNotNone(blip)
                    image_id = blip.get("{" + NS["r"] + "}embed")
                    relationships = ET.fromstring(archive.read("word/_rels/document.xml.rels"))
                    image_target = next((rel.get("Target") for rel in relationships
                                         if rel.get("Id") == image_id), None)
                    self.assertIsNotNone(image_target, "Diagram relationship is missing")
                    self.assertEqual("word/" + image_target, media[0])

                    actual = Counter(text_of(p) for p in body.findall(".//w:p", NS))
                    for paragraph, count in expected_paragraphs(source).items():
                        self.assertGreaterEqual(
                            actual[paragraph], count,
                            "Source text not found in Word document: " + repr(paragraph),
                        )
                    all_text = "".join(n.text or "" for n in body.iter(W + "t"))
                    self.assertIn(BASELINE, all_text)
                    self.assertIn(hashlib.sha256(source_bytes).hexdigest(), all_text)
                    self.assertIn(module, all_text)
                    self.assertNotIn("[[DIAGRAM:", all_text)

                    headings = []
                    for p in body.findall(".//w:p", NS):
                        style = p.find("./w:pPr/w:pStyle", NS)
                        if style is not None and style.get(W + "val", "").startswith("Heading"):
                            headings.append(text_of(p))
                    for heading in REQUIRED_HEADINGS:
                        self.assertTrue(any(h == heading or h.startswith(heading + " ")
                                            for h in headings), heading)
                    for section in ("Resource Consumption", "Synthesis Analysis",
                                    "Power Analysis", "Debug and Trace"):
                        self.assertTrue(any(section in h for h in headings), section)
                    self.assertIn("TBD", all_text)

                    bookmarks = [b.get(W + "name") for b in body.findall(".//w:bookmarkStart", NS)]
                    self.assertEqual(len(bookmarks), len(set(bookmarks)), "Duplicate bookmark")
                    links = [h.get(W + "anchor") for h in body.findall(".//w:hyperlink", NS)
                             if h.get(W + "anchor")]
                    self.assertGreaterEqual(len(links), len(REQUIRED_HEADINGS))
                    self.assertTrue(set(links).issubset(set(bookmarks)), "Broken navigation link")
                    self.assertEqual(docx_ports(body), rtl_ports(ROOT / rtl_path))

    def test_important_contracts_are_present(self):
        expected = {
            "aes_core_spec": ("E50", "E5", "69c4e0d86a7b0430d8cdb78070b4c55a", "AES_LOW_AREA"),
            "snow3g_core_spec": ("E33", "E34", "c54058f7", "advance", "35.216"),
            "zuc_core_spec": ("E33", "E34", "27bede74", "advance", "35.222"),
            "mdm_sec_spec": ("rsp_mac_match", "rsp_error", "MAX_BYTES", "65531",
                             "16,512", "EIA0", "B-4", "B+4", "zeroization"),
        }
        for stem, strings in expected.items():
            source = (SOURCE_DIR / (stem + ".md")).read_text(encoding="utf-8")
            for value in strings:
                with self.subTest(document=stem, text=value):
                    self.assertIn(value.lower(), source.lower())


if __name__ == "__main__":
    unittest.main(verbosity=2)
