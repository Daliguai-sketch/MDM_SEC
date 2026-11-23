#!/usr/bin/env python3
"""Locally render the extra vector-style RTL specification figures.

The drawings are deliberately in English because the only required image font
is DejaVu Sans.  The surrounding Markdown/DOCX gives Chinese captions and
explains the abbreviations.  No diagram adds a register to the actual RTL.
"""
from PIL import Image, ImageDraw, ImageFont
import math
from pathlib import Path

W, H = 1800, 1000
NAVY = "#173451"
INK = "#263C51"
TEAL = "#006F76"
WIRE = "#3D718D"
MUTED = "#526C7D"
BORDER = "#809CAF"
PALE = "#EAF2F7"
GREEN = "#E8F4EC"
BLUE = "#EAF0FB"
AMBER = "#FFF2D9"
PINK = "#FCEDEF"
WHITE = "#FFFFFF"
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"


def font(size, bold=False):
    candidates = ([BOLD, "C:/Windows/Fonts/arialbd.ttf"] if bold else
                  [FONT, "C:/Windows/Fonts/arial.ttf"])
    path = next((p for p in candidates if Path(p).is_file()), None)
    return ImageFont.truetype(path, size) if path else ImageFont.load_default(size=size)


def page(title, subtitle, height=H):
    image = Image.new("RGB", (W, height), WHITE)
    draw = ImageDraw.Draw(image)
    draw.text((45, 34), title, fill=NAVY, font=font(42, True))
    draw.text((48, 94), subtitle, fill=MUTED, font=font(27))
    draw.line((45, 145, W-45, 145), fill="#B7CCD9", width=3)
    return image, draw


def fit(draw, text, max_width, size=31, bold=False, minimum=23):
    f = font(size, bold)
    while draw.textlength(text, font=f) > max_width and f.size > minimum:
        f = font(f.size - 1, bold)
    if draw.textlength(text, font=f) > max_width:
        raise ValueError("Diagram label does not fit: " + text)
    return f


def text(draw, xy, value, size=29, color=INK, bold=False, anchor="lt"):
    draw.text(xy, value, fill=color, font=font(size, bold), anchor=anchor)


def box(draw, rect, title, lines=(), fill=PALE):
    x0, y0, x1, y1 = rect
    draw.rounded_rectangle(rect, radius=16, fill=fill, outline=BORDER, width=3)
    tf = fit(draw, title, x1-x0-24, 31, True, 22)
    fs = [fit(draw, line, x1-x0-24, 28, False, 21) for line in lines]
    # Font metrics rather than text bounding boxes leave room for descenders.
    height = 38 + 36*len(lines)
    y = (y0+y1-height)/2
    draw.text(((x0+x1)/2, y), title, fill=NAVY, font=tf, anchor="mt")
    for i, (line, f) in enumerate(zip(lines, fs)):
        draw.text(((x0+x1)/2, y+40+i*36), line, fill=INK, font=f, anchor="mt")


def arrow(draw, points, color=WIRE, width=5):
    draw.line(points, fill=color, width=width, joint="curve")
    x0, y0 = points[-2]
    x1, y1 = points[-1]
    a = math.atan2(y1-y0, x1-x0)
    length = 18
    spread = 0.53
    draw.polygon([(x1, y1),
                  (x1-length*math.cos(a-spread), y1-length*math.sin(a-spread)),
                  (x1-length*math.cos(a+spread), y1-length*math.sin(a+spread))], fill=color)


def line_label(draw, xy, value, size=25, color=MUTED):
    draw.text(xy, value, fill=color, font=font(size), anchor="lt", stroke_width=3, stroke_fill=WHITE)


def aes_flow():
    im, d = page("AES-128 encryption algorithm", "Column-major state; algorithmic flow, not an added hardware pipeline")
    # Wires are drawn first so that the nodes remain visually distinct.
    for a, b in [(250, 290), (460, 530), (750, 790), (1010, 1050), (1270, 1310)]:
        arrow(d, [(a, 330), (b, 330)])
    arrow(d, [(1530, 330), (1650, 330), (1650, 525), (560, 525), (560, 610)])
    arrow(d, [(790, 680), (830, 680)])
    arrow(d, [(1050, 680), (1090, 680)])
    arrow(d, [(1310, 680), (1380, 680)])
    # Loop is symbolic: it denotes rounds 1 through 9, not a new register.
    arrow(d, [(1420, 245), (1420, 185), (640, 185), (640, 245)])
    box(d, (55, 255, 250, 405), "Input", ["128-bit block"], GREEN)
    box(d, (290, 255, 460, 405), "XOR K0", ["initial"], AMBER)
    for rect, title, lines in [
        ((530, 255, 750, 405), "SubBytes", ["16 byte S-boxes"]),
        ((790, 255, 1010, 405), "ShiftRows", ["fixed permutation"]),
        ((1050, 255, 1270, 405), "MixColumns", ["4 GF columns"]),
        ((1310, 255, 1530, 405), "XOR Kr", ["round key"]),
    ]:
        box(d, rect, title, lines, BLUE)
    text(d, (820, 210), "repeat for r = 1 ... 9", 28, TEAL, True)
    box(d, (530, 610, 790, 750), "SubBytes", ["round 10"], BLUE)
    box(d, (830, 610, 1050, 750), "ShiftRows", ["round 10"], BLUE)
    box(d, (1090, 610, 1310, 750), "XOR K10", ["no MixColumns"], AMBER)
    box(d, (1380, 610, 1700, 750), "Ciphertext", ["128-bit output"], GREEN)
    box(d, (70, 820, 1730, 935), "Online key expansion", ["K0 = input key; RotWord / SubWord / Rcon produce K1 ... K10"], PALE)
    text(d, (85, 465), "Each round consumes its corresponding 128-bit key.", 29, INK)
    return im


def aes_sbox():
    im, d = page("AES S-box: exact 8-to-8-bit mapping", "Mathematical definition; the RTL implements a combinational Boolean network")
    for a, b in [(280, 365), (720, 810), (1305, 1400)]:
        arrow(d, [(a, 375), (b, 375)])
    box(d, (60, 285, 280, 465), "Input x", ["8-bit byte"], GREEN)
    box(d, (365, 275, 720, 475), "GF inverse", ["v = x^(-1)", "0 maps to 0", "mod 0x11b"], BLUE)
    box(d, (810, 275, 1305, 475), "Affine transform", ["v xor ROTL8(v,1...4)", "xor 0x63"], AMBER)
    box(d, (1400, 285, 1740, 465), "Output S(x)", ["8-bit byte"], GREEN)
    box(d, (110, 580, 1690, 710), "Example", ["x = 0x53  ->  inverse v = 0xca  ->  S(x) = 0xed"], PALE)
    text(d, (100, 790), "16 data bytes use this same mapping; the key SubWord uses it too.", 30, INK)
    text(d, (100, 850), "See the complete 16 x 16 substitution table in the specification text.", 29, MUTED)
    return im


def aes_key_schedule():
    im, d = page("AES-128 round-key expansion", "One expansion step from 4 old 32-bit words to 4 new words")
    for a, b in [(320, 410), (680, 770), (1060, 1150)]:
        arrow(d, [(a, 310), (b, 310)])
    for a, b in [(445, 485), (855, 895), (1265, 1305)]:
        arrow(d, [(a, 650), (b, 650)])
    arrow(d, [(1430, 395), (1430, 465), (205, 465), (205, 560)])
    box(d, (70, 230, 320, 390), "Old W3", ["low word of key"], GREEN)
    box(d, (410, 230, 680, 390), "RotWord", ["1 byte left"], BLUE)
    box(d, (770, 230, 1060, 390), "SubWord", ["4 AES S-boxes"], BLUE)
    box(d, (1150, 220, 1705, 400), "T", ["SubWord(RotWord(W3))", "xor {Rcon, 24'b0}"], AMBER)
    box(d, (65, 560, 445, 740), "New W0'", ["W0 xor T"], PALE)
    box(d, (485, 560, 855, 740), "New W1'", ["W1 xor W0'"], PALE)
    box(d, (895, 560, 1265, 740), "New W2'", ["W2 xor W1'"], PALE)
    box(d, (1305, 560, 1725, 740), "New W3'", ["W3 xor W2'"], PALE)
    text(d, (160, 815), "New round key = { W0', W1', W2', W3' }", 33, NAVY, True)
    text(d, (160, 875), "Rcon: 01 02 04 08 10 20 40 80 1b 36 (hex)", 29, MUTED)
    return im


def aes_add_key():
    im, d = page("AddRoundKey: bitwise XOR", "The initial AddRoundKey uses K0; each later round uses its expanded Kr")
    xs = [65, 485, 905, 1325]
    for i, x in enumerate(xs):
        arrow(d, [(x+90, 355), (x+90, 500), (x+205, 500), (x+205, 545)])
        arrow(d, [(x+300, 355), (x+300, 500), (x+205, 500), (x+205, 545)])
        arrow(d, [(x+205, 685), (x+205, 770)])
        box(d, (x, 205, x+180, 355), f"State C{i}", ["32 bits"], GREEN)
        box(d, (x+220, 205, x+400, 355), f"Key C{i}", ["32 bits"], AMBER)
        box(d, (x+60, 545, x+350, 685), "XOR", ["bitwise"], BLUE)
        box(d, (x+35, 770, x+375, 910), f"Output C{i}", ["32 bits"], PALE)
    text(d, (185, 947), "Each output bit is the XOR of the corresponding state and key bits.", 28, MUTED)
    return im


def trace(draw, x, y, dx, values, label):
    """Digital waveform: one value per interval, the first is before E0."""
    text(draw, (48, y+5), label, 28, NAVY, True)
    top, low = y+6, y+44
    points = []
    for i, value in enumerate(values):
        yy = top if value else low
        if i == 0:
            points.append((x, yy))
        else:
            points.append((x+i*dx, top if values[i-1] else low))
            points.append((x+i*dx, yy))
        points.append((x+(i+1)*dx, yy))
    draw.line(points, fill=TEAL, width=5, joint="curve")


def band(draw, x, y, dx, labels, title, colors=None):
    text(draw, (48, y+12), title, 28, NAVY, True)
    for i, value in enumerate(labels):
        color = colors[i] if colors else (PALE if i % 2 == 0 else WHITE)
        rect = (x+i*dx, y, x+(i+1)*dx, y+54)
        draw.rectangle(rect, fill=color, outline="#9CB4C3", width=2)
        f = fit(draw, str(value), dx-8, 25, False, 15)
        draw.text((x+(i+0.5)*dx, y+12), str(value), font=f, fill=INK, anchor="mt")


def wave_grid(draw, x, dx, labels, bottom):
    text(draw, (x+dx/2, 180), "pre", 26, MUTED, anchor="mt")
    for i, label in enumerate(labels):
        xpos = x+(i+1)*dx
        draw.line((xpos, 215, xpos, bottom), fill="#D9E4EB", width=2)
        text(draw, (xpos, 180), label, 26, MUTED, anchor="mt")


def aes_pair_timing():
    im, d = page("AES 5-cycle timing: back-to-back blocks", "E0 and E5 accept A and B; traces show values between sampling edges")
    x, dx = 260, 125
    wave_grid(d, x, dx, [f"E{i}" for i in range(11)], 890)
    trace(d, x, 235, dx, [1,0,0,0,0,1,0,0,0,0,0,0], "start")
    trace(d, x, 315, dx, [1,0,0,0,0,1,0,0,0,0,1,1], "ready")
    trace(d, x, 395, dx, [0,1,1,1,1,1,1,1,1,1,1,0], "busy")
    trace(d, x, 475, dx, [0,0,0,0,0,0,1,0,0,0,0,1], "done")
    band(d, x, 580, dx, ["-", "0", "1", "2", "3", "4", "0", "1", "2", "3", "4", "-"], "pair")
    band(d, x, 670, dx, ["old"]*6+["C(A)"]*5+["C(B)"], "block_out")
    text(d, (260, 790), "pair 0..4 performs rounds (1,2), (3,4), (5,6), (7,8), (9,10).", 28, INK)
    text(d, (260, 845), "At E5: result A appears after the edge while B is accepted on that edge.", 27, MUTED)
    return im


def aes_serial_timing():
    im, d = page("AES serial 50-cycle timing", "No second request in this example; the central gap omits rounds 2 through 9")
    x, dx = 260, 125
    labels = ["E0", "E1", "E2", "E3", "E4", "E5", "...", "E46", "E47", "E48", "E49", "E50"]
    # 13 intervals at 115 px each fit the figure width.
    dx = 115
    wave_grid(d, x, dx, labels, 870)
    trace(d, x, 240, dx, [1]+[0]*12, "start")
    trace(d, x, 325, dx, [1]+[0]*10+[1,1], "ready")
    trace(d, x, 410, dx, [0]+[1]*11+[0], "busy")
    trace(d, x, 495, dx, [0]*12+[1], "done")
    band(d, x, 610, dx, ["-", "K1", "C0", "C1", "C2", "C3", "...", "K10", "C0", "C1", "C2", "C3", "idle"], "next edge")
    text(d, (260, 740), "K = expand key; C0..C3 = data columns. E50 outputs the block.", 29, INK)
    text(d, (260, 800), "ready rises after E49: a new block may also be accepted at E50.", 29, MUTED)
    return im


def stream_flow(which):
    is_snow = which == "SNOW 3G"
    injection = "F into LFSR" if is_snow else "W[31:1] into LFSR"
    im, d = page(f"{which} algorithm and control flow", "INIT and DISCARD update automatically; WORK updates only on advance")
    for a, b in [(350, 405), (720, 775), (1085, 1140)]:
        arrow(d, [(a, 390), (b, 390)])
    arrow(d, [(1470, 490), (1470, 585)])
    arrow(d, [(1470, 735), (1470, 820), (1750, 820), (1750, 390), (1700, 390)])
    box(d, (70, 285, 350, 495), "start", ["load key / IV", "clear FSM regs"], GREEN)
    box(d, (405, 285, 720, 495), "INIT x 32", ["update FSM + LFSR", injection], BLUE)
    box(d, (775, 285, 1085, 495), "DISCARD x 1", ["update FSM + LFSR", "no injection"], AMBER)
    box(d, (1140, 285, 1700, 495), "WORK: valid = 1", ["output current 32-bit Z", "advance=0 holds state and Z"], GREEN)
    box(d, (1220, 585, 1700, 735), "advance = 1", ["consume current Z; update state"], BLUE)
    text(d, (100, 610), "start overrides any phase and reloads key / IV.", 30, INK)
    text(d, (100, 680), "Do not count a word on a simultaneous restart.", 30, MUTED)
    text(d, (100, 830), "No length / done: the parent controls how many words are consumed.", 28, MUTED)
    return im


def stream_timing():
    im, d = page("SNOW 3G / ZUC stream timing", "Example: consume Z0 at E34, stall twice, then consume Z1 at E37")
    x, dx = 300, 145
    labels = ["E0", "E1", "...", "E32", "E33", "E34", "E35", "E36", "E37"]
    wave_grid(d, x, dx, labels, 865)
    trace(d, x, 240, dx, [1,0,0,0,0,0,0,0,0,0], "start")
    trace(d, x, 325, dx, [0,0,0,0,0,1,1,1,1,1], "valid")
    trace(d, x, 410, dx, [0,0,0,0,0,1,0,0,1,0], "advance")
    band(d, x, 525, dx, ["IDLE", "INIT", "INIT", "...", "DISCARD", "WORK", "WORK", "WORK", "WORK", "WORK"], "state")
    band(d, x, 625, dx, ["invalid"]*5+["Z0", "Z1", "Z1", "Z1", "Z2"], "word_out")
    text(d, (300, 760), "E33: first word becomes valid after the edge; earliest sample is E34.", 29, INK)
    text(d, (300, 815), "advance=0 at E35/E36 freezes all stream state and keeps Z1 stable.", 29, MUTED)
    return im


def snow_s_transform():
    im, d = page("SNOW 3G S1 / S2 word transform", "S1 uses the AES table and 0x1b; S2 uses SQ and 0x69")
    for i in range(4):
        x = 120+i*405
        arrow(d, [(x+150, 340), (x+150, 415)])
        arrow(d, [(x+150, 565), (x+150, 650), (900, 650), (900, 700)])
        box(d, (x, 205, x+300, 340), f"Input byte {i}", ["MSB to LSB"], GREEN)
        box(d, (x, 415, x+300, 565), "S-box", ["S1: AES; S2: SQ"], BLUE)
    box(d, (510, 700, 1290, 875), "4 x 4 GF byte matrix", ["coefficients 01, 02, 03", "S1: x^8 reduction 1b; S2: 69"], AMBER)
    text(d, (1340, 760), "32-bit output", 30, NAVY, True)
    arrow(d, [(1290, 785), (1320, 785)])
    return im


def zuc_round():
    im, d = page("ZUC bit reconstruction and nonlinear F", "All paths use the old LFSR / R1 / R2 values in one combinational update")
    arrow(d, [(340, 340), (420, 340)])
    arrow(d, [(690, 340), (770, 340)])
    arrow(d, [(1080, 300), (1180, 300)])
    arrow(d, [(1450, 300), (1530, 300)])
    arrow(d, [(930, 440), (930, 525), (575, 525), (575, 575)])
    arrow(d, [(930, 440), (930, 525), (1245, 525), (1245, 575)])
    arrow(d, [(750, 670), (840, 670)])
    arrow(d, [(1440, 670), (1510, 670)])
    arrow(d, [(950, 225), (950, 180), (200, 180), (200, 250)])
    arrow(d, [(600, 430), (600, 480), (1130, 480), (1130, 340), (1180, 340)])
    line_label(d, (1020, 450), "X3", 25)
    box(d, (55, 250, 340, 430), "LFSR", ["s[0..15]: 31b"], GREEN)
    box(d, (420, 250, 690, 430), "BR", ["X0, X1, X2, X3"], BLUE)
    box(d, (770, 225, 1080, 440), "F", ["W, W1, W2", "old R1 / R2"], BLUE)
    box(d, (1180, 225, 1450, 375), "W xor X3", ["current Z"], AMBER)
    box(d, (1530, 225, 1750, 375), "word_out", ["32 bits"], GREEN)
    box(d, (350, 575, 750, 765), "L1 + S", ["low W1 / high W2", "S0 S1 S0 S1"], BLUE)
    box(d, (840, 595, 1100, 745), "R1 next", ["32-bit reg"], PALE)
    box(d, (1110, 575, 1440, 765), "L2 + S", ["low W2 / high W1", "S0 S1 S0 S1"], BLUE)
    box(d, (1510, 595, 1755, 745), "R2 next", ["32-bit reg"], PALE)
    text(d, (370, 825), "INIT only: inject W[31:1] into LFSR feedback (not Z).", 30, TEAL, True)
    text(d, (370, 875), "WORK: output is W xor X3; advance updates both LFSR and R registers.", 28, MUTED)
    return im


def mdm_eea2():
    im, d = page("EEA2: AES counter-mode data flow", "Counter blocks and message words are MSB-first; the two slots only buffer keystream")
    arrow(d, [(350, 280), (430, 280), (430, 325), (500, 325)])
    arrow(d, [(350, 445), (430, 445), (430, 385), (500, 385)])
    arrow(d, [(770, 355), (840, 355)])
    arrow(d, [(1080, 355), (1150, 355)])
    arrow(d, [(1430, 355), (1500, 355)])
    arrow(d, [(1620, 445), (1620, 545), (975, 545), (975, 635)])
    arrow(d, [(410, 720), (800, 720)])
    arrow(d, [(1150, 720), (1430, 720)])
    box(d, (55, 205, 350, 355), "prefix64", ["COUNT, bearer, dir, 0"], GREEN)
    box(d, (55, 370, 350, 520), "counter64", ["0, 1, 2, ..."], AMBER)
    box(d, (500, 275, 770, 435), "Concatenate", ["prefix || counter"], PALE)
    box(d, (840, 275, 1080, 435), "u_aes", ["E_K(block)"], BLUE)
    box(d, (1150, 275, 1430, 435), "ks0 / ks1", ["2 x 128-bit slots"], PALE)
    box(d, (1500, 265, 1750, 445), "Select word", ["ks_index 0..3", "MSB first"], BLUE)
    box(d, (80, 635, 410, 805), "Message", ["1..4 input bytes"], GREEN)
    box(d, (800, 635, 1150, 805), "XOR + byte mask", ["keystream xor data"], AMBER)
    box(d, (1430, 635, 1740, 805), "Result", ["1..4 output bytes"], GREEN)
    text(d, (120, 900), "Advance counter on an accepted AES request; advance word index on data transfer.", 29, MUTED)
    return im


def mdm_eia1():
    im, d = page("EIA1: SNOW 3G and GF(2^64) MAC", "Z0 is the first valid post-initialization word; partial message blocks are zero-padded")
    arrow(d, [(410, 260), (500, 260)])
    arrow(d, [(760, 260), (820, 260), (820, 345), (210, 345), (210, 390)])
    arrow(d, [(760, 260), (850, 260), (850, 390)])
    arrow(d, [(760, 260), (1550, 260), (1550, 390)])
    arrow(d, [(210, 530), (210, 570), (550, 570), (550, 620)])
    arrow(d, [(850, 530), (850, 570), (1010, 570), (1010, 620)])
    arrow(d, [(1550, 530), (1550, 620)])
    arrow(d, [(300, 710), (365, 710)])
    arrow(d, [(760, 710), (830, 710)])
    arrow(d, [(1220, 710), (1300, 710)])
    box(d, (60, 185, 410, 335), "u_snow", ["key + integrity IV"], GREEN)
    box(d, (500, 185, 760, 335), "Z0 ... Z4", ["five words"], BLUE)
    box(d, (65, 390, 355, 530), "P", ["Z0 || Z1"], AMBER)
    box(d, (710, 390, 990, 530), "Q", ["Z2 || Z3"], AMBER)
    box(d, (1410, 390, 1690, 530), "Z4", ["32-bit mask"], AMBER)
    box(d, (50, 620, 300, 800), "Message", ["M_i: 64-bit blocks", "zero-pad last"], GREEN)
    box(d, (365, 620, 760, 800), "Accumulator", ["V0 = 0", "Vi = (Vi-1 xor Mi) * P"], BLUE)
    box(d, (830, 620, 1220, 800), "Final multiply", ["F = (V xor L) * Q", "L = message bits"], BLUE)
    box(d, (1300, 620, 1690, 800), "MAC", ["F[63:32] xor Z4"], GREEN)
    text(d, (130, 895), "Multiplication is in GF(2^64), reduced by x^64 + x^4 + x^3 + x + 1.", 29, MUTED)
    return im


def mdm_eia3():
    im, d = page("EIA3: ZUC window-based MAC", "All bit positions start at the first valid keystream word Z0, MSB first")
    arrow(d, [(350, 280), (440, 280)])
    arrow(d, [(770, 280), (850, 280)])
    arrow(d, [(1190, 280), (1280, 280)])
    arrow(d, [(600, 195), (600, 170), (1530, 170), (1530, 195)])
    arrow(d, [(1040, 365), (1040, 430), (580, 430), (580, 545)])
    arrow(d, [(1440, 365), (1440, 470), (1110, 470), (1110, 545)])
    arrow(d, [(340, 630), (390, 630)])
    arrow(d, [(770, 630), (840, 630)])
    arrow(d, [(1190, 630), (1280, 630)])
    box(d, (60, 195, 350, 365), "u_zuc", ["key + integrity IV"], GREEN)
    box(d, (440, 195, 770, 365), "Z0 || Z1 || ...", ["32-bit words"], BLUE)
    box(d, (850, 195, 1190, 365), "Window W(i)", ["32 bits at bit i", "zcur / znext"], PALE)
    box(d, (1280, 195, 1690, 365), "Final values", ["W(L)", "Z[ceil(L/32)+1]"], AMBER)
    box(d, (60, 545, 340, 715), "Message", ["M[0..L-1]", "MSB first"], GREEN)
    box(d, (390, 545, 770, 715), "Conditional XOR", ["if M[i]=1: T ^= W(i)", "T starts at zero"], BLUE)
    box(d, (840, 545, 1190, 715), "Final XOR", ["T xor W(L) xor", "Z[ceil(L/32)+1]"], AMBER)
    box(d, (1280, 545, 1690, 715), "MAC", ["32-bit result"], GREEN)
    text(d, (160, 835), "One 32-bit input word examines up to 32 message bits; a partial tail uses valid bits only.", 28, INK)
    text(d, (160, 900), "Empty message: MAC = Z0 xor Z1; after prefetch, input stalls hold the stream.", 28, MUTED)
    return im


def mdm_cipher_lane():
    im, d = page("u_cipher: confidentiality lane", "32-bit MSB-first datapath; the three keystream primitives are independent instances")
    # Data path left to right.
    arrow(d, [(310, 810), (1210, 810)])
    arrow(d, [(1440, 810), (1510, 810)])
    # Four alternative key streams to the select mux.
    for yy in [235, 365, 495, 625]:
        arrow(d, [(1070, yy), (1120, yy), (1120, 650), (1210, 650)])
    arrow(d, [(1330, 710), (1330, 750)])
    box(d, (60, 185, 1070, 285), "EEA0", ["zero keystream (bypass)"], PALE)
    box(d, (60, 315, 1070, 415), "EEA1: u_snow", ["key + repeated prefix IV -> 32-bit stream"], BLUE)
    box(d, (60, 445, 1070, 545), "EEA2: u_aes", ["prefix64 || counter64 -> AES -> two 128-bit slots -> 32-bit word"], BLUE)
    box(d, (60, 575, 1070, 675), "EEA3: u_zuc", ["key + repeated prefix IV -> 32-bit stream"], BLUE)
    box(d, (1210, 590, 1440, 710), "alg mux", ["keystream"], AMBER)
    box(d, (60, 750, 310, 870), "in_data", ["32 bits"], GREEN)
    box(d, (1210, 750, 1440, 870), "XOR + mask", ["1..4 bytes"], AMBER)
    box(d, (1510, 745, 1740, 875), "out_data", ["out_bytes"], GREEN)
    text(d, (65, 930), "IDLE / ACTIVE, left and issued control; transfer advances stream and AES slot index.", 28, MUTED)
    return im


def mdm_integrity_lane():
    im, d = page("u_integrity: authentication lane", "32-bit input; independent SNOW, AES and ZUC instances, selected by alg")
    # Message fans out only to algorithms which consume it.
    for yy in [390, 540, 690]:
        arrow(d, [(320, 535), (365, 535), (365, yy), (450, yy)])
        arrow(d, [(1300, yy), (1360, yy), (1360, 535), (1450, 535)])
    arrow(d, [(1300, 240), (1400, 240), (1400, 535), (1450, 535)])
    box(d, (50, 420, 320, 650), "in_data", ["32-bit words", "final bytes masked", "valid / ready"], GREEN)
    box(d, (450, 180, 1300, 300), "EIA0", ["MAC = 0; immediate done; no input words"], PALE)
    box(d, (450, 325, 1300, 455), "EIA1: u_snow", ["Z0..Z4 -> P, Q, Z4; 64-bit GF accumulator"], BLUE)
    box(d, (450, 475, 1300, 605), "EIA2: u_aes", ["prefix + message -> CMAC chain; K1 / K2 -> high 32 bits"], BLUE)
    box(d, (450, 625, 1300, 755), "EIA3: u_zuc", ["two-word Z window + message bits -> XOR accumulator"], BLUE)
    box(d, (1450, 420, 1755, 650), "MAC + done", ["32-bit result", "selected by alg"], AMBER)
    text(d, (100, 840), "Length, prefix / IV, per-algorithm state and input readiness are controlled locally.", 29, MUTED)
    return im


def mdm_cmac():
    im, d = page("EIA2 AES-CMAC construction", "The prefix is an actual 8-byte part of the CMAC input, including an empty payload")
    arrow(d, [(370, 280), (430, 280)])
    arrow(d, [(720, 280), (780, 280)])
    arrow(d, [(1030, 280), (1090, 280)])
    arrow(d, [(1310, 280), (1430, 280)])
    for a, b in [(300, 350), (595, 660), (960, 1025), (1315, 1380), (1560, 1620)]:
        arrow(d, [(a, 650), (b, 650)])
    arrow(d, [(1200, 355), (1200, 565)])
    arrow(d, [(1535, 355), (1535, 480), (1250, 480), (1250, 565)])
    arrow(d, [(475, 735), (475, 785), (1170, 785), (1170, 735)])
    line_label(d, (650, 755), "last message block", 24)
    box(d, (70, 205, 370, 355), "Zero block", ["128'h0"], GREEN)
    box(d, (430, 205, 720, 355), "AES(K)", ["L = E_K(0)"], BLUE)
    box(d, (780, 205, 1030, 355), "double", ["GF(2^128)"], PALE)
    box(d, (1090, 205, 1310, 355), "K1", ["complete"], AMBER)
    box(d, (1430, 205, 1650, 355), "K2", ["partial"], AMBER)
    # K2 is the second doubling; label on the connecting edge avoids ambiguity.
    line_label(d, (1320, 245), "double", 22)
    box(d, (45, 565, 300, 735), "Message", ["prefix || data"], GREEN)
    box(d, (350, 565, 595, 735), "Split", ["128-bit blocks"], PALE)
    box(d, (660, 565, 960, 735), "CBC chain", ["non-final blocks", "X starts at zero"], BLUE)
    box(d, (1025, 565, 1315, 735), "Final block", ["full xor K1", "pad 1,0... xor K2"], AMBER)
    box(d, (1380, 565, 1560, 735), "AES(K)", ["X xor final"], BLUE)
    box(d, (1620, 565, 1770, 735), "MAC", ["high 32b"], GREEN)
    text(d, (165, 820), "For each non-final block: X = E_K(X xor M); if none, X = 0.", 30, INK)
    text(d, (165, 880), "The final block and chosen subkey are XORed with X before the final AES.", 29, MUTED)
    return im


def mdm_interaction():
    im, d = page("MDM_SEC: lane interaction via shared buffer", "Both lanes can start on the same RUN edge; paths are not direct lane-to-lane wiring")
    # The two opposite paths on the cipher side occupy distinct rows.
    arrow(d, [(665, 385), (470, 385)])
    arrow(d, [(470, 495), (665, 495)])
    arrow(d, [(1135, 430), (1325, 430)])
    arrow(d, [(1500, 565), (1500, 690), (1135, 690), (1135, 750)])
    arrow(d, [(665, 790), (300, 790), (300, 565)])
    arrow(d, [(900, 320), (900, 250)])
    box(d, (70, 305, 470, 565), "u_cipher", ["read B / MAC tail", "32-bit EEA transform", "out + byte count"], BLUE)
    box(d, (665, 320, 1135, 565), "u_input_buffer", ["16 byte banks", "rd0: 128b; rd1: 32b", "synchronous write"], GREEN)
    box(d, (1325, 305, 1725, 565), "u_integrity", ["read A + selected B", "32-bit EIA input", "calculated MAC"], BLUE)
    box(d, (665, 750, 1135, 925), "Controller", ["pointers + dependency gates", "mac_q / rx_mac_q"], AMBER)
    box(d, (600, 165, 1200, 250), "Host output after response", ["rd0 -> 128-bit result stream"], PALE)
    line_label(d, (485, 348), "rd0: B", 25)
    line_label(d, (480, 505), "result writeback", 25)
    line_label(d, (1147, 390), "rd1: A/B", 25)
    line_label(d, (1190, 665), "done / MAC", 25)
    line_label(d, (315, 758), "mode 2 MAC tail", 24)
    text(d, (60, 955), "Mode 5: controller captures the trailing decrypted MAC and compares it with calculated MAC.", 25, MUTED)
    return im


def mdm_dependencies():
    im, d = page("In-place buffer dependency examples", "One word shown; actual stalls depend on the lane algorithms and relative byte positions")
    # Swimlanes make the order and the read-during-write behavior explicit.
    box(d, (65, 195, 300, 385), "Modes 2 / 4", ["integrity reads", "original B"], AMBER)
    box(d, (380, 195, 950, 385), "Before / at edge E", ["integrity reads old B", "cipher can write same bytes at E"], GREEN)
    box(d, (1040, 195, 1730, 385), "After edge E", ["buffer contains transformed B", "same-edge read sampled old B"], BLUE)
    arrow(d, [(300, 290), (380, 290)])
    arrow(d, [(950, 290), (1040, 290)])
    box(d, (65, 490, 300, 680), "Modes 3 / 5", ["integrity reads", "cipher result"], AMBER)
    box(d, (380, 490, 950, 680), "At edge E", ["cipher writes result to buffer", "integrity cannot yet use it"], GREEN)
    box(d, (1040, 490, 1730, 680), "At edge E+1 or later", ["integrity may read committed result", "subject to its own readiness"], BLUE)
    arrow(d, [(300, 585), (380, 585)])
    arrow(d, [(950, 585), (1040, 585)])
    text(d, (100, 770), "Mode 2 also waits for int_finished before consuming any appended MAC byte.", 30, INK)
    text(d, (100, 835), "Same-edge old-data behavior depends on asynchronous read / synchronous write.", 28, MUTED)
    text(d, (100, 885), "A replacement SRAM must preserve this behavior or the scheduler must change.", 28, MUTED)
    return im


def mdm_packet_timing():
    im, d = page("MDM_SEC exact handshake example", "Mode 4, EEA0/EIA0, A=5 B=3 bytes; chosen response/output stalls", height=1220)
    x, dx = 260, 125
    wave_grid(d, x, dx, [f"E{i}" for i in range(11)], 1110)
    trace(d, x, 225, dx, [1]+[0]*11, "cmd_valid")
    trace(d, x, 295, dx, [1]+[0]*10+[1], "cmd_ready")
    trace(d, x, 365, dx, [0,1,1]+[0]*9, "in_valid")
    trace(d, x, 435, dx, [0,1,1]+[0]*9, "in_ready")
    trace(d, x, 505, dx, [0,0,0,1]+[0]*8, "lane_start")
    trace(d, x, 575, dx, [0]*7+[1,1,0,0,0], "rsp_valid")
    trace(d, x, 645, dx, [0]*8+[1,0,0,0], "rsp_ready")
    trace(d, x, 715, dx, [0]*9+[1,1,0], "cipher_valid")
    trace(d, x, 785, dx, [0]*10+[1,0], "cipher_ready")
    band(d, x, 880, dx, ["IDLE", "LOAD_A", "LOAD_B", "RUN", "RUN", "RUN", "RUN", "RSP", "RSP", "OUT", "OUT", "IDLE"], "state")
    band(d, x, 965, dx, ["-", "A", "B"]+["-"]*9, "in_data")
    text(d, (260, 1050), "E0 cmd; E1 A; E2 B; E3 both starts; E8 response; E10 output.", 28, INK)
    text(d, (260, 1100), "This bypass example is RTL-checked; other algorithms change RUN duration.", 28, MUTED)
    return im


def mdm_protocol():
    im, d = page("MDM_SEC packet protocol and backpressure", "Illustrative ordering; RUN duration and stall lengths are not fixed cycle counts")
    # Each column is an interval, not an implied fixed implementation latency.
    x, dx = 265, 145
    labels = ["cmd", "A", "B", "start", "RUN", "rsp wait", "rsp", "out wait", "out", "idle"]
    text(d, (x+dx/2, 180), "phase", 27, MUTED, anchor="mt")
    for i, lab in enumerate(labels):
        f = fit(d, lab, dx-5, 24, False, 18)
        d.text((x+(i+0.5)*dx, 218), lab, fill=MUTED, font=f, anchor="mt")
        d.line((x+i*dx, 260, x+i*dx, 800), fill="#DCE7ED", width=2)
    d.line((x+len(labels)*dx, 260, x+len(labels)*dx, 800), fill="#DCE7ED", width=2)
    def row(y, title, values):
        band(d, x, y, dx, values, title)
    row(280, "controller", ["IDLE", "LOAD_A", "LOAD_B", "RUN", "RUN...", "RESPONSE", "RESPONSE", "OUTPUT", "OUTPUT", "IDLE"])
    row(370, "handshake", ["cmd", "in A", "in B", "starts", "wait", "stall", "rsp", "stall", "cipher", "-"])
    row(460, "rsp_valid", ["0", "0", "0", "0", "0", "1", "1", "0", "0", "0"])
    row(550, "cipher_valid", ["0", "0", "0", "0", "0", "0", "0", "1", "1", "0"])
    row(640, "ready", ["cmd=1", "in=1", "in=1", "-", "-", "rsp=0", "rsp=1", "out=0", "out=1", "cmd=1"])
    text(d, (265, 760), "Example: one A beat, one B beat and one output beat; both lanes enabled.", 28, INK)
    text(d, (265, 815), "During stalls valid and payload stay stable; handshake occurs only on a clock edge.", 27, MUTED)
    text(d, (265, 870), "Empty segments, errors, and multi-beat packets take different paths.", 27, MUTED)
    return im


def mdm_mode2_5():
    im, d = page("Modes 2 and 5: append, transform and verify", "Arrows describe logical data dependencies, not a promise of whole-packet serialization")
    # Mode 2.
    arrow(d, [(320, 300), (420, 300)])
    arrow(d, [(750, 300), (850, 300)])
    arrow(d, [(1160, 300), (1250, 300)])
    arrow(d, [(1500, 300), (1570, 300)])
    arrow(d, [(180, 220), (180, 180), (1005, 180), (1005, 220)])
    line_label(d, (795, 158), "B bypass", 24)
    box(d, (55, 220, 320, 380), "A || B", ["original bytes"], GREEN)
    box(d, (420, 220, 750, 380), "Integrity", ["MAC = int(A || B)"], BLUE)
    box(d, (850, 220, 1160, 380), "Append MAC", ["B || MAC, MSB first"], AMBER)
    box(d, (1250, 220, 1500, 380), "Cipher", ["enc / XOR"], BLUE)
    box(d, (1570, 220, 1750, 380), "Output", ["B + 4"], GREEN)
    text(d, (65, 405), "Mode 2", 28, TEAL, True)
    # Mode 5.
    arrow(d, [(320, 650), (400, 650)])
    arrow(d, [(660, 650), (760, 650)])
    arrow(d, [(1060, 650), (1160, 650)])
    arrow(d, [(1450, 650), (1520, 650)])
    arrow(d, [(910, 730), (910, 805), (1640, 805), (1640, 730)])
    line_label(d, (1070, 610), "P only", 24)
    line_label(d, (1210, 775), "rx MAC", 24)
    box(d, (55, 570, 320, 730), "Ciphertext B", ["includes MAC"], GREEN)
    box(d, (400, 570, 660, 730), "Cipher", ["decrypt / XOR"], BLUE)
    box(d, (760, 570, 1060, 730), "P || rx MAC", ["last 4 bytes"], AMBER)
    box(d, (1160, 570, 1450, 730), "Integrity", ["int(A || P)"], BLUE)
    box(d, (1520, 570, 1750, 730), "Compare", ["match flag"], AMBER)
    text(d, (65, 755), "Mode 5", 28, TEAL, True)
    text(d, (65, 840), "P is emitted after the response even when match = 0; the system must discard it.", 29, INK)
    text(d, (65, 895), "EIA0 MAC = 0 is not authentication security.", 28, MUTED)
    return im


EXTRA_DIAGRAMS = {
    "aes_flow": aes_flow,
    "aes_sbox_map": aes_sbox,
    "aes_key_schedule": aes_key_schedule,
    "aes_add_key": aes_add_key,
    "aes_pair_timing": aes_pair_timing,
    "aes_serial_timing": aes_serial_timing,
    "snow_flow": lambda: stream_flow("SNOW 3G"),
    "zuc_flow": lambda: stream_flow("ZUC-128"),
    "stream_timing": stream_timing,
    "snow_s_transform": snow_s_transform,
    "zuc_round": zuc_round,
    "mdm_cipher_lane": mdm_cipher_lane,
    "mdm_integrity_lane": mdm_integrity_lane,
    "mdm_eea2": mdm_eea2,
    "mdm_eia1": mdm_eia1,
    "mdm_eia3": mdm_eia3,
    "mdm_cmac": mdm_cmac,
    "mdm_interaction": mdm_interaction,
    "mdm_dependencies": mdm_dependencies,
    "mdm_packet_timing": mdm_packet_timing,
    "mdm_protocol": mdm_protocol,
    "mdm_mode2_5": mdm_mode2_5,
}
