#!/usr/bin/env python3
"""Check balanced-opt hierarchy after Yosys synthesis and top elaboration."""
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


def check_top(path):
    modules = json.loads(path.read_text())["modules"]
    for lane in ("u_cipher", "u_integrity"):
        lane_type = child(modules, "mdm_sec", lane)
        aes_type = child(modules, lane_type, "u_aes")
        # Some frontends add an enclosing genblkN for the else-if chain.
        matches = [name for name, cell in modules[aes_type]["cells"].items()
                   if (name == "g_balanced_timing.u_core" or
                       name.endswith(".g_balanced_timing.u_core"))
                   and cell["type"] == "mdm_aes128_balanced_timing"]
        if len(matches) != 1:
            fail(f"{lane}.u_aes does not contain exactly one balanced-opt core: {matches}")
        child(modules, aes_type, matches[0], "mdm_aes128_balanced_timing")
    counts = walk(modules, "mdm_sec")
    for name, count in (("mdm_aes128_balanced_timing", 2),
                        ("mdm_aes_sbox", 16), ("mdm_aes_sbox_timing", 64),
                        ("mdm_aes_balanced_mix_column_timing", 16),
                        ("mdm_aes_balanced_add_round_key", 8)):
        if counts[name] != count:
            fail(f"Top expected {count} instances of {name}; got {counts[name]}")
    if counts["mdm_aes128_balanced"]:
        fail("Retired balanced core is still instantiated")
    print("PASS mdm_sec AES_LOW_AREA=2: independent balanced-opt cores in both lanes")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--synth", type=Path, required=True)
    parser.add_argument("--top", type=Path, required=True)
    args = parser.parse_args()
    check_timing_synth(args.synth)
    check_top(args.top)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
