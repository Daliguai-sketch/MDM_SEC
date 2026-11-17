#!/usr/bin/env python3
"""Check the source-extension and one-semicolon-per-line coding rules."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]


def semicolons_by_line(text):
    """Find code semicolons, ignoring //, /* */ and quoted strings."""
    positions = []
    in_block = False
    for line in text.splitlines():
        items = []
        in_string = False
        escaped = False
        i = 0
        while i < len(line):
            char = line[i]
            pair = line[i:i + 2]
            if in_block:
                if pair == "*/":
                    in_block = False
                    i += 2
                    continue
            elif in_string:
                if escaped:
                    escaped = False
                elif char == "\\":
                    escaped = True
                elif char == '"':
                    in_string = False
            elif pair == "//":
                break
            elif pair == "/*":
                in_block = True
                i += 2
                continue
            elif char == '"':
                in_string = True
            elif char == ";":
                items.append(i)
            i += 1
        positions.append(items)
    return positions


def main():
    rtl = ROOT / "rtl"
    errors = []
    for path in sorted(rtl.rglob("*.sv")):
        errors.append(f"{path.relative_to(ROOT)}: RTL must use .v, not .sv")
    sources = sorted(rtl.rglob("*.v")) + sorted(rtl.rglob("*.vh"))
    # Verification sources are not synthesized RTL; they may use .sv, but
    # follow the same one-semicolon rule for readability.
    sources += sorted((ROOT / "tests" / "rtl").rglob("*.sv"))
    sources += sorted((ROOT / "examples").rglob("*.sv"))
    if not sources:
        errors.append("No Verilog sources found")
    for path in sources:
        for line_no, positions in enumerate(semicolons_by_line(path.read_text()), 1):
            if len(positions) > 1:
                errors.append(f"{path.relative_to(ROOT)}:{line_no}: {len(positions)} code semicolons")

    # All six controller/primitive FSMs use explicit, ordered sections.
    # The state-register section must clock only state; the next-state
    # section must assign only next_state. Datapath registers are separate.
    fsm_names = ("mdm_aes128", "mdm_snow3g", "mdm_zuc", "mdm_cipher", "mdm_integrity", "mdm_sec")
    markers = ("FSM section 1:", "FSM section 2:", "FSM section 3:")
    for name in fsm_names:
        path = rtl / f"{name}.v"
        text = path.read_text()
        indices = [text.find(marker) for marker in markers]
        if min(indices) < 0 or not (indices[0] < indices[1] < indices[2]):
            errors.append(f"{path.relative_to(ROOT)}: missing or unordered FSM sections")
            continue
        state_part = text[indices[0]:indices[1]]
        next_part = text[indices[1]:indices[2]]
        state_assigns = re.findall(r"\b([A-Za-z_]\w*)\s*<=", state_part)
        next_assigns = re.findall(r"\b([A-Za-z_]\w*)\s*=(?!=)", next_part)
        all_state_assigns = list(re.finditer(r"\bstate\s*<=", text))
        if len(state_assigns) != 2 or set(state_assigns) != {"state"}:
            errors.append(f"{path.relative_to(ROOT)}: state register section mixes assignments")
        if len(all_state_assigns) != 2 or not all(indices[0] < item.start() < indices[1] for item in all_state_assigns):
            errors.append(f"{path.relative_to(ROOT)}: FSM state assigned outside its register section")
        if not next_assigns or set(next_assigns) != {"next_state"}:
            errors.append(f"{path.relative_to(ROOT)}: next-state section mixes assignments")
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print(f"PASS RTL .v extension, three-section FSMs and one semicolon per line ({len(sources)} Verilog files)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
