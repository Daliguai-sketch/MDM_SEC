#!/usr/bin/env python3
"""Validate checked-in DOCX RTL specifications using only the standard library.

Checks include DOCX ZIP/XML integrity, source-to-DOCX content, navigation,
all linked/embedded figures, complete S-box tables, required chapters, and
every public RTL port name/direction/width. It does not replace an engineering
or layout review.
"""
import ast
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
    "wp": "http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing",
}
W = "{" + NS["w"] + "}"
BASELINE = "938ac3409dbcf2c2bc4244f4b3d60f1b19da0c4c"
DOCUMENTS = {
    "aes_core_spec": ("rtl/mdm_aes128.v", "mdm_aes128"),
    "aes_balanced_core_spec": ("rtl/mdm_aes128_balanced_timing.v", "mdm_aes128_balanced_timing"),
    "snow3g_core_spec": ("rtl/mdm_snow3g.v", "mdm_snow3g"),
    "zuc_core_spec": ("rtl/mdm_zuc.v", "mdm_zuc"),
    "mdm_sec_spec": ("rtl/mdm_sec.v", "mdm_sec"),
}
FIGURE_PATTERN = re.compile(r"!\[([^\]\n]+)\]\(\.\./figures/([a-z][a-z0-9_]*)\.png\)")
REQUIRED_FIGURES = {
    "aes_core_spec": {"aes", "aes_flow", "aes_sbox_map", "aes_key_schedule", "aes_add_key",
                      "aes_pair_timing", "aes_serial_timing"},
    "aes_balanced_core_spec": {"aes_balanced", "aes_flow", "aes_sbox_map", "aes_key_schedule",
                               "aes_add_key", "aes_pair_timing"},
    "snow3g_core_spec": {"snow", "snow_flow", "snow_s_transform", "stream_timing"},
    "zuc_core_spec": {"zuc", "zuc_flow", "zuc_round", "stream_timing"},
    "mdm_sec_spec": {"mdm", "mdm_cipher_lane", "mdm_integrity_lane", "mdm_interaction",
                     "mdm_dependencies", "mdm_protocol", "mdm_packet_timing", "mdm_mode2_5",
                     "mdm_cmac", "mdm_eea2", "mdm_eia1", "mdm_eia3"},
}
REQUIRED_SBOXES = {
    "aes_core_spec": {"AES"},
    "aes_balanced_core_spec": {"AES"},
    "snow3g_core_spec": {"AES", "SNOW_SQ"},
    "zuc_core_spec": {"ZUC_S0", "ZUC_S1"},
    "mdm_sec_spec": set(),
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
        if not line or FIGURE_PATTERN.fullmatch(line):
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


def rtl_ports(path, module):
    """Read ANSI-style ports of the named module (files can contain several)."""
    text = path.read_text(encoding="utf-8")
    matches = list(re.finditer(r"^\s*module\s+" + re.escape(module) + r"\b", text, re.MULTILINE))
    if len(matches) != 1:
        raise AssertionError(f"Expected exactly one {module} module in {path}")
    header = text[matches[0].start():].split(");", 1)[0]
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


def python_list_constant(path, name):
    tree = ast.parse(path.read_text(encoding="utf-8"))
    for node in tree.body:
        if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == name
                                               for t in node.targets):
            return ast.literal_eval(node.value)
    raise AssertionError(f"Missing reference constant {name} in {path}")


def rtl_case_table(name):
    text = (ROOT / "rtl/mdm_sboxes.vh").read_text(encoding="utf-8")
    pairs = re.findall(r"8'h([0-9a-f]{2}):\s*" + re.escape(name) +
                       r"\s*=\s*8'h([0-9a-f]{2})", text, re.IGNORECASE)
    mapping = {int(index, 16): int(value, 16) for index, value in pairs}
    if len(pairs) != 256 or set(mapping) != set(range(256)):
        raise AssertionError("S-box is not a complete one-to-one indexed table: " + name)
    return [mapping[i] for i in range(256)]


def documented_sboxes(source):
    pattern = re.compile(r"^#### [^\n]*\(SBOX_([A-Z0-9_]+)\)\n\n```text\n(.*?)\n```",
                         re.MULTILINE | re.DOTALL)
    result = {}
    for name, content in pattern.findall(source):
        if name in result:
            raise AssertionError("Duplicate documented S-box: " + name)
        lines = content.splitlines()
        if len(lines) != 17 or lines[0].split() != ["hi/lo"] + list("0123456789abcdef"):
            raise AssertionError("Bad S-box header or row count: " + name)
        values = []
        for i, row in enumerate(lines[1:]):
            fields = row.split()
            if len(fields) != 17 or fields[0] != f"{i:x}0" or any(
                    not re.fullmatch(r"[0-9a-f]{2}", value) for value in fields[1:]):
                raise AssertionError(f"Bad S-box row {i} in {name}")
            values.extend(int(value, 16) for value in fields[1:])
        result[name] = values
    return result


def aes_sbox_from_equation():
    def mul(a, b):
        result = 0
        for _ in range(8):
            if b & 1:
                result ^= a
            a = ((a << 1) & 255) ^ (0x1b if a & 0x80 else 0)
            b >>= 1
        return result

    def inverse(x):
        if x == 0:
            return 0
        result, base, exponent = 1, x, 254
        while exponent:
            if exponent & 1:
                result = mul(result, base)
            base = mul(base, base)
            exponent >>= 1
        return result

    def rotl8(x, n):
        return ((x << n) | (x >> (8-n))) & 255

    return [v ^ rotl8(v, 1) ^ rotl8(v, 2) ^ rotl8(v, 3) ^ rotl8(v, 4) ^ 0x63
            for v in map(inverse, range(256))]


def rtl_snow_matrix(name):
    text = (ROOT / "rtl/mdm_sboxes.vh").read_text(encoding="utf-8")
    match = re.search(r"function automatic \[31:0\] " + re.escape(name) +
                      r"\(.*?endfunction", text, re.DOTALL)
    if not match:
        raise AssertionError("Missing RTL matrix " + name)
    pairs = re.findall(r"if \(x\[(\d)\]\).*?32'h([0-9a-f]{8})", match.group(), re.I)
    matrix = {int(bit): int(value, 16) for bit, value in pairs}
    if len(pairs) != 8 or set(matrix) != set(range(8)):
        raise AssertionError("Malformed RTL matrix " + name)
    return [matrix[i] for i in range(8)]


def snow_gf_mapping(x, powers):
    def mulxpow(value, count):
        for _ in range(count):
            value = ((value << 1) & 255) ^ (0xa9 if value & 0x80 else 0)
        return value
    return sum(mulxpow(x, power) << (24-8*i) for i, power in enumerate(powers))


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
                    figures = [(m.group(1), m.group(2)) for m in FIGURE_PATTERN.finditer(source)]
                    self.assertTrue(REQUIRED_FIGURES[stem].issubset({kind for _, kind in figures}),
                                    "Missing required algorithm, timing or architecture figure")
                    drawings = body.findall(".//w:drawing", NS)
                    self.assertEqual(len(drawings), len(figures), "Source/Word figure count differs")
                    relationships = ET.fromstring(archive.read("word/_rels/document.xml.rels"))
                    rels = {rel.get("Id"): rel.get("Target") for rel in relationships
                            if rel.get("TargetMode") != "External"}
                    used_media = set()
                    for number, ((label, kind), drawing) in enumerate(zip(figures, drawings), 1):
                        props = drawing.find(".//wp:docPr", NS)
                        self.assertIsNotNone(props, "Missing accessible figure metadata")
                        self.assertEqual(props.get("title"), kind)
                        self.assertEqual(props.get("descr"), f"图 {number}  {label}")
                        blip = drawing.find(".//a:blip", NS)
                        self.assertIsNotNone(blip)
                        target = rels.get(blip.get("{" + NS["r"] + "}embed"))
                        self.assertIsNotNone(target, "Diagram relationship is missing")
                        media_path = "word/" + target
                        self.assertIn(media_path, names)
                        used_media.add(media_path)
                        image = archive.read(media_path)
                        self.assertEqual(image, (SPEC_DIR / "figures" / (kind + ".png")).read_bytes(),
                                         "Markdown and Word figure bytes differ: " + kind)
                        self.assertEqual(image[:8], b"\x89PNG\r\n\x1a\n")
                        width, height = struct.unpack(">II", image[16:24])
                        self.assertGreaterEqual(width, 1000)
                        self.assertGreaterEqual(height, 500)
                    self.assertEqual(used_media, {n for n in names if n.startswith("word/media/")})

                    actual = Counter(text_of(p) for p in body.findall(".//w:p", NS))
                    for number, (label, _) in enumerate(figures, 1):
                        self.assertGreaterEqual(actual[f"图 {number}  {label}"], 1,
                                                "Figure caption is missing")
                    for paragraph, count in expected_paragraphs(source).items():
                        self.assertGreaterEqual(
                            actual[paragraph], count,
                            "Source text not found in Word document: " + repr(paragraph),
                        )
                    all_text = "".join(n.text or "" for n in body.iter(W + "t"))
                    if stem in ("aes_core_spec", "aes_balanced_core_spec", "mdm_sec_spec"):
                        # New/updated specs must not identify their RTL as the
                        # old baseline, which predates the optimized AES core.
                        self.assertIn("本文档所在 Git 提交的 RTL", all_text)
                        self.assertNotIn(BASELINE, all_text)
                    else:
                        self.assertIn(BASELINE, all_text)
                    self.assertIn("V0.3 / Draft", all_text)
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
                    source_headings = re.findall(r"^#{1,4}\s+.+$", source, re.MULTILINE)
                    self.assertEqual(len(bookmarks), len(source_headings))
                    self.assertEqual(len(links), len(source_headings))
                    self.assertEqual(set(links), set(bookmarks), "Broken or missing navigation link")
                    self.assertEqual(docx_ports(body), rtl_ports(ROOT / rtl_path, module))

    def test_figure_inventory(self):
        referenced = set()
        for stem in DOCUMENTS:
            source = (SOURCE_DIR / (stem + ".md")).read_text(encoding="utf-8")
            referenced.update(match.group(2) for match in FIGURE_PATTERN.finditer(source))
        present = {p.stem for p in (SPEC_DIR / "figures").glob("*.png")}
        self.assertEqual(present, referenced, "Missing or orphaned Markdown figure")

    def test_retired_aes_sources_are_not_in_current_specs(self):
        for stem in ("aes_core_spec", "aes_balanced_core_spec", "mdm_sec_spec"):
            source = (SOURCE_DIR / (stem + ".md")).read_text(encoding="utf-8")
            with self.subTest(document=stem):
                self.assertIn("balanced-opt", source)
                for retired in ("rtl/mdm_aes128_balanced.v", "rtl/mdm_aes_mix_balanced.vh",
                                "test-balanced-fallback"):
                    self.assertNotIn(retired, source)

    def test_complete_documented_sboxes(self):
        aes_golden = [int(x, 16) for x in (ROOT / "tests/rtl/aes_sbox.hex").read_text().split()]
        snow_py = ROOT / "sec_core/snow3g/sec_snow3g_core.py"
        zuc_py = ROOT / "sec_core/zuc/sec_zuc_core.py"
        expected = {
            "AES": aes_golden,
            "SNOW_SQ": rtl_case_table("snow_sq"),
            "ZUC_S0": rtl_case_table("zuc_s0"),
            "ZUC_S1": rtl_case_table("zuc_s1"),
        }
        self.assertEqual(expected["AES"], aes_sbox_from_equation())
        self.assertEqual(expected["AES"], python_list_constant(snow_py, "SR"))
        self.assertEqual(expected["SNOW_SQ"], python_list_constant(snow_py, "SQ"))
        self.assertEqual(expected["ZUC_S0"], python_list_constant(zuc_py, "S0"))
        self.assertEqual(expected["ZUC_S1"], python_list_constant(zuc_py, "S1"))
        for stem, required in REQUIRED_SBOXES.items():
            source = (SOURCE_DIR / (stem + ".md")).read_text(encoding="utf-8")
            documented = documented_sboxes(source)
            self.assertEqual(set(documented), required, stem)
            for name, values in documented.items():
                with self.subTest(document=stem, sbox=name):
                    self.assertEqual(len(values), 256)
                    self.assertEqual(values, expected[name])

    def test_snow_feedback_matrices_match_documented_powers(self):
        for name, powers in (("snow_mulalpha", (23, 245, 48, 239)),
                             ("snow_divalpha", (16, 39, 6, 64))):
            matrix = rtl_snow_matrix(name)
            for x in range(256):
                actual = 0
                for bit in range(8):
                    if x & (1 << bit):
                        actual ^= matrix[bit]
                with self.subTest(matrix=name, value=x):
                    self.assertEqual(actual, snow_gf_mapping(x, powers))

    def test_important_contracts_are_present(self):
        expected = {
            "aes_core_spec": ("E50", "E5", "69c4e0d86a7b0430d8cdb78070b4c55a", "AES_LOW_AREA",
                              "BALANCED_TIMING_OPT", "g_balanced_timing"),
            "aes_balanced_core_spec": ("E5", "AES_LOW_AREA=2", "7,321", "7,097",
                                       "AES_INTEGRITY_TIMING_OPT", "mdm_aes128_balanced_timing",
                                       "70", "67", "69c4e0d86a7b0430d8cdb78070b4c55a"),
            "snow3g_core_spec": ("E33", "E34", "c54058f7", "advance", "35.216"),
            "zuc_core_spec": ("E33", "E34", "27bede74", "advance", "35.222"),
            "mdm_sec_spec": ("rsp_mac_match", "rsp_error", "MAX_BYTES", "65531",
                             "AES_INTEGRITY_TIMING_OPT", "16,512", "EIA0", "B-4", "B+4", "zeroization",
                             "u_inte", "u_integrity", "enc_mem_ready", "int_dep_ready",
                             "tb_spec_timing.sv", "GF64_MUL", "prefix64"),
        }
        for stem, strings in expected.items():
            source = (SOURCE_DIR / (stem + ".md")).read_text(encoding="utf-8")
            for value in strings:
                with self.subTest(document=stem, text=value):
                    self.assertIn(value.lower(), source.lower())


if __name__ == "__main__":
    unittest.main(verbosity=2)
