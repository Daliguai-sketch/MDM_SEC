#!/usr/bin/env python3
"""Check balanced AES hierarchy after Yosys synthesis and top elaboration."""
import argparse
from collections import Counter
import json
from pathlib import Path
import sys


def fail(message):
    raise ValueError(message)


def child(modules, parent, instance, expected=None):
    try:
        cell = modules[parent]["cells"][instance]
        actual = cell["type"]
        module = modules[actual]
    except KeyError as exc:
        fail(f"Missing hierarchy {parent}.{instance}: {exc}")
    if module.get("attributes", {}).get("blackbox", "0").strip("0"):
        fail(f"{parent}.{instance} is a black box")
    if expected is not None and actual != expected:
        fail(f"{parent}.{instance}: expected {expected}, got {actual}")
    return actual


def walk(modules, root, parents=()):
    if root in parents:
        fail(f"Recursive module hierarchy at {root}")
    totals = Counter({root: 1})
    for cell in modules[root]["cells"].values():
        if cell["type"] in modules:
            totals.update(walk(modules, cell["type"], parents + (root,)))
    return totals


def check_synth(path):
    modules = json.loads(path.read_text())["modules"]
    root = "mdm_aes128_balanced"
    child(modules, root, "u_initial_add_round_key", "mdm_aes_balanced_add_round_key")
    k1 = child(modules, root, "u_key_expand1", "mdm_aes_balanced_key_expand1")
    k2 = child(modules, root, "u_key_expand2", "mdm_aes_balanced_key_expand2")
    for key in (k1, k2):
        subword = child(modules, key, "u_subword", "mdm_aes_subbytes4")
        for i in range(4):
            child(modules, subword, f"g_byte[{i}].u_sbox", "mdm_aes_sbox")
    child(modules, k1, "u_word_xor", "mdm_aes_key_expand")

    for index in (1, 2):
        rnd = child(modules, root, f"u_round{index}")
        if modules[rnd].get("attributes", {}).get("hdlname") != "mdm_aes_balanced_round":
            fail(f"u_round{index} is not a balanced round")
        default = modules[rnd].get("parameter_default_values", {}).get("MAY_SKIP_MIX")
        if default is None or int(default, 2) != index - 1:
            fail(f"u_round{index} has wrong final-round bypass specialization")
        sb = child(modules, rnd, "u_subbytes", "mdm_aes_balanced_subbytes")
        child(modules, rnd, "u_shift_rows", "mdm_aes_shift_rows")
        mc = child(modules, rnd, "u_mix_columns", "mdm_aes_balanced_mix_columns")
        child(modules, rnd, "u_add_round_key", "mdm_aes_balanced_add_round_key")
        for i in range(16):
            child(modules, sb, f"g_byte[{i}].u_sbox", "mdm_aes_sbox")
        for i in range(4):
            child(modules, mc, f"g_column[{i}].u_mix_column", "mdm_aes_balanced_mix_column")
    for name, kind in (("u_top", "mdm_aes_sbox_linear_top"),
                       ("u_nonlinear", "mdm_aes_sbox_nonlinear"),
                       ("u_bottom", "mdm_aes_sbox_linear_bottom")):
        child(modules, "mdm_aes_sbox", name, kind)

    counts = walk(modules, root)
    for module, count in (("mdm_aes_sbox", 40), ("mdm_aes_balanced_mix_column", 8),
                          ("mdm_aes_balanced_add_round_key", 3)):
        if counts[module] != count:
            fail(f"Expected {count} instances of {module}; got {counts[module]}")
    print("PASS synthesized standalone hierarchy: 2 rounds, 2 key expansions, "
          "40 S-boxes, 8 MixColumns, 3 AddRoundKey")

    def generic_cells(module):
        # synth -noabc maps each generic leaf to one cell. Nested totals are
        # inclusive; do not add them to their already-included parent totals.
        return sum(generic_cells(cell["type"]) if cell["type"] in modules else 1
                   for cell in modules[module]["cells"].values())

    print("Generic cells, inclusive per hierarchy (not physical area):")
    local = sum(cell["type"] not in modules for cell in modules[root]["cells"].values())
    print(f"  core local (excludes children): {local}")
    for name in ("u_initial_add_round_key", "u_key_expand1", "u_key_expand2", "u_round1", "u_round2"):
        module = modules[root]["cells"][name]["type"]
        print(f"  {name}: {generic_cells(module)}")
        if name in ("u_round1", "u_round2"):
            for stage in ("u_subbytes", "u_shift_rows", "u_mix_columns", "u_add_round_key"):
                stage_type = modules[module]["cells"][stage]["type"]
                print(f"    {stage}: {generic_cells(stage_type)}")
    print(f"  total per AES core: {generic_cells(root)}")


def check_timing_synth(path):
    modules = json.loads(path.read_text())["modules"]
    root = "mdm_aes128_balanced_timing"
    child(modules, root, "u_initial_add_round_key", "mdm_aes_balanced_add_round_key")
    for name, kind in (("u_key_expand1", "mdm_aes_balanced_key_expand1"),
                       ("u_key_expand2", "mdm_aes_balanced_key_expand2")):
        child(modules, root, name, kind)
    for index in (1, 2):
        rnd = child(modules, root, f"u_round{index}")
        if modules[rnd].get("attributes", {}).get("hdlname") != "mdm_aes_balanced_round_timing":
            fail(f"u_round{index} is not a timing-oriented balanced round")
        default = modules[rnd].get("parameter_default_values", {}).get("WITH_LAST_OUTPUT")
        if default is None or int(default, 2) != index - 1:
            fail(f"u_round{index} has wrong separate-final-output specialization")
        sb = child(modules, rnd, "u_subbytes", "mdm_aes_balanced_subbytes_timing")
        child(modules, rnd, "u_shift_rows", "mdm_aes_shift_rows")
        mc = child(modules, rnd, "u_mix_columns", "mdm_aes_balanced_mix_columns_timing")
        child(modules, rnd, "u_add_round_key", "mdm_aes_balanced_add_round_key")
        if index == 2:
            child(modules, rnd, "g_last_add_round_key.u_add_round_key", "mdm_aes_balanced_add_round_key")
        if any(cell["type"] in ("$mux", "$_MUX_") for cell in modules[rnd]["cells"].values()):
            fail(f"u_round{index} unexpectedly contains a data selection mux")
        for i in range(16):
            child(modules, sb, f"g_byte[{i}].u_sbox", "mdm_aes_sbox_timing")
        for i in range(4):
            child(modules, mc, f"g_column[{i}].u_mix_column", "mdm_aes_balanced_mix_column_timing")
    counts = walk(modules, root)
    for name, expected in (("mdm_aes_sbox", 8), ("mdm_aes_sbox_timing", 32),
                           ("mdm_aes_balanced_mix_column_timing", 8),
                           ("mdm_aes_balanced_add_round_key", 4)):
        if counts[name] != expected:
            fail(f"Expected {expected} instances of {name}; got {counts[name]}")

    def generic_cells(module):
        return sum(generic_cells(cell["type"]) if cell["type"] in modules else 1
                   for cell in modules[module]["cells"].values())

    print("PASS synthesized timing core: 32 flat data S-boxes, 8 hierarchical key S-boxes, "
          "8 depth-oriented MixColumns, separate final AddRoundKey")
    print(f"  timing core total (generic cells, not physical area): {generic_cells(root)}")
    for name in ("u_initial_add_round_key", "u_key_expand1", "u_key_expand2", "u_round1", "u_round2"):
        kind = modules[root]["cells"][name]["type"]
        print(f"  {name}: {generic_cells(kind)} inclusive generic cells")


def check_top(path, *, timing_enabled):
    modules = json.loads(path.read_text())["modules"]
    expected = (("u_cipher", "g_balanced", "mdm_aes128_balanced"),
                ("u_integrity", "g_balanced_timing" if timing_enabled else "g_balanced",
                 "mdm_aes128_balanced_timing" if timing_enabled else "mdm_aes128_balanced"))
    for lane, label, core in expected:
        lane_type = child(modules, "mdm_sec", lane)
        aes_type = child(modules, lane_type, "u_aes")
        # Some frontends add an enclosing genblkN for the else-if chain.
        matches = [name for name, cell in modules[aes_type]["cells"].items()
                   if (name == f"{label}.u_core" or name.endswith(f".{label}.u_core"))
                   and cell["type"] == core]
        if len(matches) != 1:
            fail(f"{lane}.u_aes does not contain exactly one {label}.u_core: {matches}")
        child(modules, aes_type, matches[0], core)
    counts = walk(modules, "mdm_sec")
    expected_counts = ({"mdm_aes128_balanced": 1, "mdm_aes128_balanced_timing": 1,
                        "mdm_aes_sbox": 48, "mdm_aes_sbox_timing": 32} if timing_enabled else
                       {"mdm_aes128_balanced": 2, "mdm_aes128_balanced_timing": 0,
                        "mdm_aes_sbox": 80, "mdm_aes_sbox_timing": 0})
    for name, count in expected_counts.items():
        if counts[name] != count:
            fail(f"Top expected {count} instances of {name}; got {counts[name]}")
    print(f"PASS mdm_sec AES_LOW_AREA=2: independent cipher/original and "
          f"integrity/{'timing' if timing_enabled else 'original'} hierarchies")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--synth", type=Path, required=True)
    parser.add_argument("--synth-timing", type=Path, required=True)
    parser.add_argument("--top", type=Path, required=True)
    parser.add_argument("--top-fallback", type=Path, required=True)
    args = parser.parse_args()
    check_synth(args.synth)
    check_timing_synth(args.synth_timing)
    check_top(args.top, timing_enabled=True)
    check_top(args.top_fallback, timing_enabled=False)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
