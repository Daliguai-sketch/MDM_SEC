#!/usr/bin/env python3
"""Render the checked-in RTL design specifications to editable DOCX.

Requires python-docx and Pillow. Source text is in docs/specs/src; figures are
rendered locally from simple vectors and embedded in the resulting documents.
"""
import argparse
from datetime import datetime
import hashlib
from io import BytesIO
import math
from pathlib import Path
import re
import zipfile

from docx import Document
from docx.enum.table import WD_CELL_VERTICAL_ALIGNMENT, WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Cm, Inches, Pt, RGBColor
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = ROOT / "docs/specs/src"
RTL_BASELINE = "938ac3409dbcf2c2bc4244f4b3d60f1b19da0c4c"
DATE = "2026-11-17"
DOCUMENTS = {
    "aes_core_spec": ("AES_CORE", "mdm_aes128 · AES-128 加密块原语", "aes"),
    "aes_balanced_core_spec": ("AES_BALANCED_CORE", "mdm_aes128_balanced · 5 拍面积优化 AES-128 原语", "aes_balanced"),
    "snow3g_core_spec": ("SNOW3G_CORE", "mdm_snow3g · SNOW 3G 密钥流原语", "snow"),
    "zuc_core_spec": ("ZUC_CORE", "mdm_zuc · ZUC-128 密钥流原语", "zuc"),
    "mdm_sec_spec": ("MDM_SEC", "mdm_sec · 包级安全处理顶层", "mdm"),
}

NAVY = "173451"
TEAL = "006F76"
INK = "24364B"
LIGHT = "EAF2F7"
GRID = "CBD8E3"
WHITE = "FFFFFF"
CJK_FONT = "Microsoft YaHei"
LATIN_FONT = "Calibri"
MONO_FONT = "Consolas"
CONTENT_WIDTH = 6.70


def rgb(hex_color):
    return RGBColor.from_string(hex_color)


def set_font(run, name=LATIN_FONT, size=None, bold=None, color=None):
    run.font.name = name
    if size is not None:
        run.font.size = Pt(size)
    if bold is not None:
        run.bold = bold
    if color:
        run.font.color.rgb = rgb(color)
    rpr = run._element.get_or_add_rPr()
    fonts = rpr.rFonts
    if fonts is None:
        fonts = OxmlElement("w:rFonts")
        rpr.insert(0, fonts)
    fonts.set(qn("w:ascii"), name)
    fonts.set(qn("w:hAnsi"), name)
    fonts.set(qn("w:eastAsia"), CJK_FONT)
    return run


def configure_style(style, size, color=INK, bold=False, before=0, after=4):
    style.font.name = LATIN_FONT
    style.font.size = Pt(size)
    style.font.bold = bold
    style.font.color.rgb = rgb(color)
    rpr = style.element.get_or_add_rPr()
    fonts = rpr.rFonts
    if fonts is None:
        fonts = OxmlElement("w:rFonts")
        rpr.insert(0, fonts)
    fonts.set(qn("w:ascii"), LATIN_FONT)
    fonts.set(qn("w:hAnsi"), LATIN_FONT)
    fonts.set(qn("w:eastAsia"), CJK_FONT)
    pf = style.paragraph_format
    pf.space_before = Pt(before)
    pf.space_after = Pt(after)
    pf.line_spacing = 1.17


def shade(cell, color):
    tcpr = cell._tc.get_or_add_tcPr()
    shd = tcpr.find(qn("w:shd"))
    if shd is None:
        shd = OxmlElement("w:shd")
        tcpr.append(shd)
    shd.set(qn("w:fill"), color)


def no_split(row):
    trpr = row._tr.get_or_add_trPr()
    element = OxmlElement("w:cantSplit")
    trpr.append(element)


def repeat_table_header(row):
    element = OxmlElement("w:tblHeader")
    element.set(qn("w:val"), "true")
    row._tr.get_or_add_trPr().append(element)


def set_cell_margins(table):
    tblpr = table._tbl.tblPr
    margins = tblpr.find(qn("w:tblCellMar"))
    if margins is None:
        margins = OxmlElement("w:tblCellMar")
        tblpr.append(margins)
    for side, twips in (("top", 70), ("bottom", 70), ("left", 95), ("right", 95)):
        e = OxmlElement("w:" + side)
        e.set(qn("w:w"), str(twips))
        e.set(qn("w:type"), "dxa")
        margins.append(e)


def set_table_borders(table):
    tblpr = table._tbl.tblPr
    old = tblpr.find(qn("w:tblBorders"))
    if old is not None:
        tblpr.remove(old)
    borders = OxmlElement("w:tblBorders")
    for side in ("top", "left", "bottom", "right", "insideH", "insideV"):
        edge = OxmlElement("w:" + side)
        edge.set(qn("w:val"), "single")
        edge.set(qn("w:sz"), "4")
        edge.set(qn("w:space"), "0")
        edge.set(qn("w:color"), GRID)
        borders.append(edge)
    tblpr.append(borders)


def inline_text(paragraph, text, size=None, color=None, force_bold=False):
    # The sources intentionally use only simple inline code and bold markup.
    for part in re.split(r"(`[^`]*`|\*\*[^*]+\*\*)", text):
        if not part:
            continue
        if part.startswith("`") and part.endswith("`"):
            set_font(paragraph.add_run(part[1:-1]), MONO_FONT, size, force_bold, color)
        elif part.startswith("**") and part.endswith("**"):
            set_font(paragraph.add_run(part[2:-2]), LATIN_FONT, size, True, color)
        else:
            set_font(paragraph.add_run(part), LATIN_FONT, size, force_bold, color)


def table_widths(headers):
    n = len(headers)
    if n == 2:
        return [1.80, CONTENT_WIDTH - 1.80]
    if n == 3:
        # Reserve most of the width for descriptions rather than identifiers.
        if headers[0] == "版本":
            return [0.85, 1.15, CONTENT_WIDTH - 2.00]
        if headers[0] == "编号" and "风险" in headers[1]:
            return [1.15, 3.70, CONTENT_WIDTH - 4.85]
        if headers[0] == "参数" and headers[1] == "默认值":
            return [1.45, 0.85, CONTENT_WIDTH - 2.30]
        if headers[0] in ("时刻", "模式", "ID"):
            return [0.85, 2.85, CONTENT_WIDTH - 3.70]
        if headers[0] == "配置":
            return [1.40, 2.15, CONTENT_WIDTH - 3.55]
        return [1.45, 2.05, CONTENT_WIDTH - 3.50]
    if n == 4 and headers[0] in ("信号", "Signal"):
        return [1.52, 0.57, 0.62, CONTENT_WIDTH - 2.71]
    if n == 4:
        return [1.10, 2.25, 1.10, CONTENT_WIDTH - 4.45]
    return [CONTENT_WIDTH / n] * n


def add_table(doc, rows):
    headers = rows[0]
    cols = len(headers)
    widths = table_widths(headers)
    table = doc.add_table(rows=0, cols=cols)
    table.autofit = False
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    set_table_borders(table)
    set_cell_margins(table)
    for col, width in enumerate(widths):
        table.columns[col].width = Inches(width)
    for index, values in enumerate(rows):
        row = table.add_row()
        no_split(row)
        if index == 0:
            repeat_table_header(row)
        for col, value in enumerate(values):
            cell = row.cells[col]
            cell.width = Inches(widths[col])
            cell.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
            shade(cell, NAVY if index == 0 else ("F3F7FA" if index % 2 == 0 else WHITE))
            paragraph = cell.paragraphs[0]
            paragraph.paragraph_format.space_before = Pt(0)
            paragraph.paragraph_format.space_after = Pt(0)
            paragraph.paragraph_format.line_spacing = 1.08
            inline_text(paragraph, value, size=9, color=WHITE if index == 0 else INK,
                        force_bold=(index == 0))
    doc.add_paragraph().paragraph_format.space_after = Pt(2)


def split_table_row(line):
    content = line.strip()
    if not content.startswith("|") or not content.endswith("|"):
        raise ValueError("Malformed table row: " + line)
    content = content[1:-1]
    cells = []
    value = []
    in_code = False
    index = 0
    while index < len(content):
        ch = content[index]
        if ch == "`":
            in_code = not in_code
            value.append(ch)
        elif ch == "\\" and index + 1 < len(content) and content[index + 1] == "|":
            value.append("|")
            index += 1
        elif ch == "|" and not in_code:
            # In this engineering text || is a byte-concatenation symbol,
            # whereas the table delimiter is a single vertical bar.
            if index + 1 < len(content) and content[index + 1] == "|":
                value.extend(("|", "|"))
                index += 1
            else:
                cells.append("".join(value).strip())
                value = []
        else:
            value.append(ch)
        index += 1
    cells.append("".join(value).strip())
    if in_code:
        raise ValueError("Unclosed inline code in table: " + line)
    return cells


def is_separator(cells):
    return all(re.fullmatch(r":?-{3,}:?", item.replace(" ", "")) for item in cells)


def font_path(bold=False):
    candidates = (["/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
                   "/usr/share/fonts/truetype/liberation2/LiberationSans-Bold.ttf",
                   "C:/Windows/Fonts/arialbd.ttf"] if bold else
                  ["/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
                   "/usr/share/fonts/truetype/liberation2/LiberationSans-Regular.ttf",
                   "C:/Windows/Fonts/arial.ttf"])
    return next((path for path in candidates if Path(path).is_file()), None)


def image_font(size, bold=False):
    path = font_path(bold)
    return ImageFont.truetype(path, size) if path else ImageFont.load_default(size=size)


def draw_box(draw, coords, title, lines, fill="#EAF2F7"):
    x0, y0, x1, y1 = coords
    draw.rounded_rectangle(coords, radius=20, fill=fill, outline="#47718E", width=4)
    center = (x0 + x1) / 2
    title_font = image_font(29, True)
    line_font = image_font(25)
    while draw.textlength(title, font=title_font) > x1 - x0 - 26 and title_font.size > 18:
        title_font = image_font(title_font.size - 1, True)
    draw.text((center, y0 + 26), title, fill="#173451", font=title_font, anchor="mt")
    for index, line in enumerate(lines):
        current_font = line_font
        while draw.textlength(line, font=current_font) > x1 - x0 - 24 and current_font.size > 17:
            current_font = image_font(current_font.size - 1)
        draw.text((center, y0 + 77 + index * 39), line, fill="#30475B", font=current_font, anchor="mt")


def arrow(draw, points, fill="#416F8A", width=6):
    draw.line(points, fill=fill, width=width, joint="curve")
    x0, y0 = points[-2]
    x1, y1 = points[-1]
    angle = math.atan2(y1 - y0, x1 - x0)
    length = 20
    spread = 0.55
    corners = [(x1, y1),
               (x1 - length * math.cos(angle - spread), y1 - length * math.sin(angle - spread)),
               (x1 - length * math.cos(angle + spread), y1 - length * math.sin(angle + spread))]
    draw.polygon(corners, fill=fill)


def canvas(title, subtitle):
    image = Image.new("RGB", (1800, 900), "white")
    draw = ImageDraw.Draw(image)
    draw.text((50, 38), title, fill="#173451", font=image_font(40, True))
    draw.text((52, 98), subtitle, fill="#527287", font=image_font(26))
    draw.line([(50, 145), (1750, 145)], fill="#B7CCD9", width=3)
    return image, draw


def diagram_aes():
    image, draw = canvas("AES-128 block core", "Static parameter selection; one AES implementation is instantiated per lane")
    arrow(draw, [(320, 470), (385, 470)])
    for y in (255, 475, 695):
        arrow(draw, [(685, 470), (730, 470), (730, y), (790, y)])
        arrow(draw, [(1350, y), (1400, y), (1400, 470), (1480, 470)])
    draw_box(draw, (35, 325, 320, 615), "Request", ["key / block: 128b", "start and ready", "single block"], "#E4F1F4")
    draw_box(draw, (385, 355, 685, 585), "Generate select", ["AES_LOW_AREA", "static 1 / 0 / 2"], "#FFF1D8")
    draw_box(draw, (790, 175, 1350, 335), "Serial  |  1  |  50 cycles", ["4 shared S-boxes", "10 rounds; II = 50"], "#E7F3EC")
    draw_box(draw, (790, 395, 1350, 555), "Original fast  |  0  |  5 cycles", ["2 rounds per cycle", "10 rounds; II = 5"], "#E8EEF9")
    draw_box(draw, (790, 615, 1350, 775), "Area-optimized  |  2  |  5 cycles", ["shared-XOR MixColumns", "10 rounds; II = 5"], "#E8EEF9")
    draw_box(draw, (1480, 325, 1760, 615), "Result", ["done pulse", "block_out: 128b", "busy / ready"], "#E4F1F4")
    return image


def diagram_aes_balanced():
    image, draw = canvas("AES-128 area-optimized core", "One block per 5 cycles; both rounds are combinational between state registers")
    arrow(draw, [(285, 495), (350, 495)])
    arrow(draw, [(620, 495), (720, 495)])
    arrow(draw, [(1010, 495), (1100, 495)])
    arrow(draw, [(1400, 495), (1485, 495)])
    arrow(draw, [(1400, 590), (1440, 590), (1440, 755), (485, 755), (485, 625)])
    arrow(draw, [(620, 400), (660, 400), (660, 255), (720, 255)])
    arrow(draw, [(880, 335), (880, 400)])
    arrow(draw, [(1250, 335), (1250, 400)])
    draw_box(draw, (35, 365, 285, 625), "Request", ["key / block_in", "start / ready", "128b"], "#E4F1F4")
    draw_box(draw, (350, 365, 620, 625), "Registers", ["round_state", "key_reg / rcon", "pair 0 to 4"], "#FFF1D8")
    draw_box(draw, (720, 175, 1400, 335), "Two-round key expansion", ["key1 then factored key2", "8 S-boxes, online per block"], "#E7F3EC")
    draw_box(draw, (720, 400, 1010, 590), "Round 1", ["16 S-boxes", "MixColumns", "AddRoundKey"], "#E8EEF9")
    draw_box(draw, (1100, 400, 1400, 590), "Round 2", ["16 S-boxes", "MixColumns bypass", "when pair = 4"], "#E8EEF9")
    draw_box(draw, (1485, 365, 1760, 625), "Result", ["done on E5", "block_out: 128b", "next request on E5"], "#E4F1F4")
    draw.text((700, 775), "feedback after rounds 2, 4, 6 and 8", fill="#527287", font=image_font(23))
    return image


def diagram_snow():
    image, draw = canvas("SNOW 3G streaming core", "Start reloads the state; INIT and DISCARD advance automatically; WORK advances on request")
    arrow(draw, [(340, 460), (440, 460)])
    arrow(draw, [(940, 420), (1030, 420)])
    arrow(draw, [(1440, 420), (1515, 420)])
    arrow(draw, [(690, 610), (690, 760), (1470, 760), (1470, 555), (1515, 555)])
    arrow(draw, [(1200, 305), (1200, 230), (690, 230), (690, 305)])
    draw_box(draw, (40, 325, 340, 610), "Load", ["key: 128b", "iv: 128b", "start overrides advance"], "#E4F1F4")
    draw_box(draw, (440, 305, 940, 610), "LFSR state", ["16 x 32b: s[0..15]", "MULalpha / DIValpha", "INIT adds F to feedback"], "#E7F3EC")
    draw_box(draw, (1030, 305, 1440, 610), "Nonlinear FSM", ["r1 / r2 / r3: 32b", "S1, S2, modulo addition", "F = (s15 + r1) XOR r2"], "#E8EEF9")
    draw_box(draw, (1515, 330, 1770, 620), "Output", ["Z = F XOR s0", "word_out: 32b", "valid / advance"], "#FFF1D8")
    draw.text((780, 190), "F feedback: INIT only", fill="#527287", font=image_font(23))
    draw.text((900, 780), "s0 to XOR", fill="#527287", font=image_font(23))
    return image


def diagram_zuc():
    image, draw = canvas("ZUC-128 streaming core", "32 INIT updates + 1 DISCARD; state advances one word per enabled WORK edge")
    arrow(draw, [(300, 455), (365, 455)])
    arrow(draw, [(745, 455), (810, 455)])
    arrow(draw, [(1060, 455), (1120, 455)])
    arrow(draw, [(1430, 455), (1500, 455)])
    arrow(draw, [(930, 585), (930, 725), (1470, 725), (1470, 555), (1500, 555)])
    arrow(draw, [(1270, 305), (1270, 215), (555, 215), (555, 305)])
    draw_box(draw, (35, 330, 300, 590), "Load", ["key / iv: 128b", "s[i] = {K, D, IV}", "start reloads"], "#E4F1F4")
    draw_box(draw, (365, 305, 745, 605), "LFSR", ["16 x 31b", "mod (2^31 - 1)", "zero maps to 7fffffff"], "#E7F3EC")
    draw_box(draw, (810, 305, 1060, 605), "Bit reconstruction", ["X0 / X1", "X2 / X3", "fixed bit slices"], "#E8EEF9")
    draw_box(draw, (1120, 305, 1430, 605), "Nonlinear F", ["R1 / R2", "L1 / L2, S0 / S1", "W and next state"], "#E8EEF9")
    draw_box(draw, (1500, 330, 1770, 620), "Output", ["Z = W XOR X3", "word_out: 32b", "valid / advance"], "#FFF1D8")
    draw.text((720, 175), "W[31:1] feedback: INIT only", fill="#527287", font=image_font(23))
    draw.text((1050, 745), "X3 bypass to XOR", fill="#527287", font=image_font(23))
    return image


def diagram_mdm():
    image, draw = canvas("MDM_SEC packet security top", "One packet at a time; two independent algorithm lanes share a byte-banked in-place buffer")
    arrow(draw, [(300, 465), (405, 465)])
    arrow(draw, [(760, 400), (890, 400)])
    arrow(draw, [(890, 495), (830, 495), (830, 575), (760, 575)])
    arrow(draw, [(760, 625), (890, 625)])
    arrow(draw, [(1320, 650), (1390, 650), (1390, 485), (1500, 485)])
    arrow(draw, [(575, 705), (575, 810), (1450, 810), (1450, 625), (1500, 625)])
    draw.line([(900, 285), (900, 320)], fill="#89A9BA", width=4)
    draw_box(draw, (365, 165, 1450, 285), "Packet controller / dependency protection", ["cmd  •  load A/B  •  launch  •  response  •  output"], "#FFF1D8")
    draw_box(draw, (30, 330, 300, 680), "Host input", ["command", "in_data: 128b", "A then B", "valid / ready"], "#E4F1F4")
    draw_box(draw, (405, 330, 760, 705), "Packet buffer", ["16 byte banks", "rd0: 128b", "rd1: 32b", "in-place B result"], "#E7F3EC")
    draw_box(draw, (890, 330, 1320, 525), "Cipher lane", ["EEA0 / SNOW / AES / ZUC", "32b stream, writeback"], "#E8EEF9")
    draw_box(draw, (890, 560, 1320, 750), "Integrity lane", ["EIA0 / SNOW / AES / ZUC", "32b stream -> MAC"], "#E8EEF9")
    draw_box(draw, (1500, 345, 1770, 700), "Host output", ["response + MAC", "cipher_data: 128b", "keep / last", "valid / ready"], "#E4F1F4")
    draw.text((785, 355), "rd0", fill="#527287", font=image_font(23))
    draw.text((770, 515), "writeback", fill="#527287", font=image_font(22))
    draw.text((800, 645), "rd1", fill="#527287", font=image_font(23))
    draw.text((1010, 825), "buffer -> output after response", fill="#527287", font=image_font(23))
    return image


def diagram_bytes(name):
    image = {"aes": diagram_aes, "aes_balanced": diagram_aes_balanced,
             "snow": diagram_snow, "zuc": diagram_zuc, "mdm": diagram_mdm}[name]()
    output = BytesIO()
    image.save(output, format="PNG", optimize=True)
    output.seek(0)
    return output


def add_figure(doc, kind):
    captions = {
        "aes": "图 1  AES-128 包装器及静态选择的三种微架构",
        "aes_balanced": "图 1  5 拍面积优化 AES-128 数据路径与轮密钥扩展",
        "snow": "图 1  SNOW 3G 原语顶层数据及反馈关系",
        "zuc": "图 1  ZUC-128 原语顶层数据及反馈关系",
        "mdm": "图 1  MDM_SEC 包级顶层结构与两条独立通道",
    }
    paragraph = doc.add_paragraph()
    paragraph.alignment = WD_ALIGN_PARAGRAPH.CENTER
    paragraph.paragraph_format.keep_with_next = True
    shape = paragraph.add_run().add_picture(diagram_bytes(kind), width=Inches(CONTENT_WIDTH))
    shape._inline.docPr.set("descr", captions[kind])
    caption = doc.add_paragraph()
    caption.alignment = WD_ALIGN_PARAGRAPH.CENTER
    caption.paragraph_format.space_after = Pt(8)
    set_font(caption.add_run(captions[kind]), size=9, color=TEAL)


def add_page_number(paragraph):
    paragraph.alignment = WD_ALIGN_PARAGRAPH.RIGHT
    set_font(paragraph.add_run("Draft  ·  Page "), size=8, color="6E8293")
    run = paragraph.add_run()
    fld = OxmlElement("w:fldSimple")
    fld.set(qn("w:instr"), "PAGE")
    text_run = OxmlElement("w:r")
    text = OxmlElement("w:t")
    text.text = "1"
    text_run.append(text)
    fld.append(text_run)
    run._r.addnext(fld)


def heading_outline(source):
    """Assign stable bookmarks to the numbered source headings, in order."""
    result = []
    in_code = False
    for line in source.splitlines():
        if line.startswith("```"):
            in_code = not in_code
            continue
        if not in_code:
            match = re.match(r"^(#{1,4})\s+(.+)$", line)
            if match:
                result.append((len(match.group(1)), match.group(2),
                               f"spec_heading_{len(result) + 1:03d}"))
    return result


def add_internal_link(paragraph, label, bookmark):
    link = OxmlElement("w:hyperlink")
    link.set(qn("w:anchor"), bookmark)
    run = OxmlElement("w:r")
    properties = OxmlElement("w:rPr")
    fonts = OxmlElement("w:rFonts")
    fonts.set(qn("w:ascii"), LATIN_FONT)
    fonts.set(qn("w:hAnsi"), LATIN_FONT)
    fonts.set(qn("w:eastAsia"), CJK_FONT)
    properties.append(fonts)
    color = OxmlElement("w:color")
    color.set(qn("w:val"), TEAL)
    properties.append(color)
    size = OxmlElement("w:sz")
    size.set(qn("w:val"), "19")  # Word half-points: 9.5 pt.
    properties.append(size)
    run.append(properties)
    text = OxmlElement("w:t")
    text.text = label
    run.append(text)
    link.append(run)
    paragraph._p.append(link)


def add_bookmark(paragraph, name, identifier):
    start = OxmlElement("w:bookmarkStart")
    start.set(qn("w:id"), str(identifier))
    start.set(qn("w:name"), name)
    end = OxmlElement("w:bookmarkEnd")
    end.set(qn("w:id"), str(identifier))
    # Paragraph properties, if present, must remain the first child.
    paragraph._p.insert(1 if paragraph._p.pPr is not None else 0, start)
    paragraph._p.append(end)


def prepare_document(name, subtitle, source_hash, outline, rtl_baseline=RTL_BASELINE):
    doc = Document()
    section = doc.sections[0]
    section.page_width, section.page_height = Cm(21.0), Cm(29.7)
    section.left_margin = section.right_margin = Cm(1.95)
    section.top_margin, section.bottom_margin = Cm(1.85), Cm(1.75)
    section.header_distance = section.footer_distance = Cm(0.85)
    section.different_first_page_header_footer = True
    styles = doc.styles
    configure_style(styles["Normal"], 10.2)
    configure_style(styles["Heading 1"], 16.5, NAVY, True, 13, 7)
    configure_style(styles["Heading 2"], 12.5, TEAL, True, 10, 5)
    configure_style(styles["Heading 3"], 11.0, NAVY, True, 8, 4)
    configure_style(styles["Heading 4"], 10.4, TEAL, True, 7, 3)
    configure_style(styles["List Bullet"], 10.2, INK, False, 0, 3)
    for level in ("Heading 1", "Heading 2", "Heading 3", "Heading 4"):
        styles[level].paragraph_format.keep_with_next = True
    header = section.header.paragraphs[0]
    set_font(header.add_run(f"MDM_SEC  /  {name}  /  RTL DESIGN SPECIFICATION"),
             size=8, color="6E8293", bold=True)
    add_page_number(section.footer.paragraphs[0])
    props = doc.core_properties
    props.title = name + " RTL Design Specification"
    props.subject = subtitle
    props.author = "MDM_SEC RTL Design"
    props.last_modified_by = "MDM_SEC RTL Design"
    props.created = datetime(2026, 11, 17)
    props.modified = datetime(2026, 11, 17)
    props.revision = 1
    props.comments = "Draft; RTL baseline " + rtl_baseline

    top = doc.add_paragraph()
    top.paragraph_format.space_before = Pt(34)
    top.paragraph_format.space_after = Pt(20)
    set_font(top.add_run("HARDWARE DESIGN  /  RTL SPECIFICATION"), size=10, bold=True, color=TEAL)
    title = doc.add_paragraph()
    title.paragraph_format.space_after = Pt(8)
    set_font(title.add_run(name), size=32, bold=True, color=NAVY)
    title2 = doc.add_paragraph()
    title2.paragraph_format.space_after = Pt(12)
    set_font(title2.add_run("RTL Design Specification"), size=22, bold=True, color=NAVY)
    sub = doc.add_paragraph()
    sub.paragraph_format.space_after = Pt(26)
    set_font(sub.add_run(subtitle), size=12, color=TEAL)
    add_table(doc, [
        ["Document Control", "Value"],
        ["版本 / 状态", "V0.1 / Draft — 待评审，非工艺与安全签核"],
        ["编制日期", DATE],
        ["RTL 基线提交", rtl_baseline],
        ["编制 / 审核 / 批准", "TBD / TBD / TBD"],
        ["内容源 SHA-256", source_hash[:32] + "\n" + source_hash[32:]],
    ])
    note = doc.add_paragraph()
    note.paragraph_format.space_before = Pt(14)
    inline_text(note, "本文件描述已实现 RTL；工艺、频率、物理面积和功耗等未提供的数据标记为 TBD。", size=10, color=INK)
    doc.add_page_break()

    doc.add_heading("Document Control and Revision History", level=1)
    add_table(doc, [["版本", "日期", "变更 / 状态"],
                    ["0.1", DATE, "依据 RTL 基线形成初版；待设计、验证、综合及安全评审。"]])
    doc.add_heading("Contents", level=1)
    guide = doc.add_paragraph("选择目录条目可跳转到对应章节。本目录由源文件生成，不含自动页码；修改章节标题后需重新生成。")
    guide.paragraph_format.space_after = Pt(6)
    for level, heading, bookmark in outline:
        if level > 3:
            continue
        paragraph = doc.add_paragraph()
        paragraph.paragraph_format.left_indent = Cm((level - 1) * 0.48)
        paragraph.paragraph_format.space_before = Pt(0)
        paragraph.paragraph_format.space_after = Pt(1)
        paragraph.paragraph_format.line_spacing = 1.0
        add_internal_link(paragraph, heading, bookmark)
    update = OxmlElement("w:updateFields")
    update.set(qn("w:val"), "true")
    doc.settings.element.append(update)
    doc.add_page_break()
    return doc


def add_code(doc, lines):
    for line in lines:
        paragraph = doc.add_paragraph()
        paragraph.paragraph_format.left_indent = Cm(0.25)
        paragraph.paragraph_format.space_after = Pt(0)
        paragraph.paragraph_format.line_spacing = 1.05
        set_font(paragraph.add_run(line if line else " "), MONO_FONT, 8.7, color=NAVY)
    doc.add_paragraph().paragraph_format.space_after = Pt(2)


def render_markdown(doc, source):
    lines = source.splitlines()
    outline = iter(heading_outline(source))
    heading_number = 0
    i = 0
    while i < len(lines):
        line = lines[i]
        if not line.strip():
            i += 1
            continue
        if line.startswith("```"):
            block = []
            i += 1
            while i < len(lines) and not lines[i].startswith("```"):
                block.append(lines[i])
                i += 1
            if i == len(lines):
                raise ValueError("Unterminated code block")
            add_code(doc, block)
            i += 1
            continue
        marker = re.fullmatch(r"\[\[DIAGRAM:(aes|aes_balanced|snow|zuc|mdm)\]\]", line.strip())
        if marker:
            add_figure(doc, marker.group(1))
            i += 1
            continue
        if line.startswith("|"):
            rows = []
            while i < len(lines) and lines[i].startswith("|"):
                row = split_table_row(lines[i])
                if not is_separator(row):
                    rows.append(row)
                i += 1
            if not rows or any(len(row) != len(rows[0]) for row in rows):
                raise ValueError("Inconsistent table columns near: " + str(rows[:2]))
            add_table(doc, rows)
            continue
        heading = re.match(r"^(#{1,4})\s+(.+)$", line)
        if heading:
            level, label, bookmark = next(outline)
            heading_number += 1
            if (level, label) != (len(heading.group(1)), heading.group(2)):
                raise ValueError("Heading/bookmark outline is inconsistent")
            paragraph = doc.add_heading(label, level=level)
            add_bookmark(paragraph, bookmark, heading_number)
        elif line.startswith("- "):
            # An explicit Unicode bullet avoids Word's legacy Symbol-font list
            # glyph, which may render as an empty box on non-Windows systems.
            p = doc.add_paragraph()
            p.paragraph_format.left_indent = Cm(0.55)
            p.paragraph_format.first_line_indent = Cm(-0.35)
            p.paragraph_format.space_after = Pt(3)
            inline_text(p, "• " + line[2:])
        else:
            p = doc.add_paragraph()
            inline_text(p, line)
        i += 1


def save_reproducible(doc, path):
    raw = BytesIO()
    doc.save(raw)
    raw.seek(0)
    # Normalize ZIP entry timestamps, making unchanged sources reproducible.
    with zipfile.ZipFile(raw, "r") as original, zipfile.ZipFile(path, "w") as result:
        for entry in original.infolist():
            data = original.read(entry.filename)
            info = zipfile.ZipInfo(entry.filename, (2020, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = entry.external_attr
            info.create_system = entry.create_system
            result.writestr(info, data, compresslevel=9)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", default=str(ROOT / "docs/specs"))
    parser.add_argument("--only", action="append", choices=DOCUMENTS,
                        help="render only this document (repeat to select several)")
    args = parser.parse_args()
    output = Path(args.output_dir).expanduser().resolve()
    output.mkdir(parents=True, exist_ok=True)
    for stem, (name, subtitle, kind) in DOCUMENTS.items():
        if args.only and stem not in args.only:
            continue
        source_path = SOURCE_DIR / (stem + ".md")
        data = source_path.read_bytes()
        source = data.decode("utf-8")
        # The optimized core is new; its exact RTL is the one committed with
        # this specification, not the older baseline used by the other specs.
        if stem in ("aes_core_spec", "aes_balanced_core_spec", "mdm_sec_spec"):
            baseline = "本文档所在 Git 提交的 RTL"
        else:
            baseline = RTL_BASELINE
        doc = prepare_document(name, subtitle, hashlib.sha256(data).hexdigest(),
                               heading_outline(source), baseline)
        render_markdown(doc, source)
        path = output / (stem + ".docx")
        save_reproducible(doc, path)
        print(f"Generated {path} ({path.stat().st_size:,} bytes)")


if __name__ == "__main__":
    main()
