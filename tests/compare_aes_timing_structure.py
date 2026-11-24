#!/usr/bin/env python3
"""Compare fast/balanced-opt AES generic gate topology; this is NOT STA.

Uses the same Yosys -noabc synthesis for both cores, then walks the flattened
single-bit generic cells. Every cell has unit weight; loads, gate sizes,
constraints, interconnect and clock paths are not modeled. The requested RTL
state bit indices are not a substitute for paths in a target mapped netlist.
"""
import argparse
from collections import Counter
from functools import lru_cache
import json
from pathlib import Path
import subprocess
import sys

from compare_aes_balanced_area import AES_RTL, ROOT


def quote(path):
    return '"' + str(path).replace("\\", "\\\\").replace('"', '\\"') + '"'


def synth(yosys, output, top, label):
    result_json = output / f"{label}.json"
    log = output / f"{label}.log"
    command = ("read_verilog -Irtl " + " ".join(AES_RTL) + "; "
               f"hierarchy -check -top {top}; synth -top {top} -noabc; "
               f"check -assert; stat; flatten; write_json {quote(result_json)}")
    with log.open("w", encoding="utf-8") as stream:
        subprocess.run([yosys, "-Q", "-T", "-p", command], cwd=ROOT, stdout=stream,
                       stderr=subprocess.STDOUT, check=True)
    if "Found and reported 0 problems." not in log.read_text(encoding="utf-8"):
        raise RuntimeError(f"Yosys did not complete the structural check: {log}")
    return measure(result_json, top)


def measure(path, top):
    module = json.loads(path.read_text(encoding="utf-8"))["modules"][top]
    state_bits = module["netnames"]["round_state"]["bits"]
    if len(state_bits) != 128:
        raise ValueError(f"{top}: expected a 128-bit round_state")

    drivers = {}
    reg_d = {}
    generic = Counter()
    for cell in module["cells"].values():
        kind = cell["type"]
        if kind == "$scopeinfo":
            continue
        if not kind.startswith("$_"):
            raise ValueError(f"Unexpected non-generic cell {kind} in {top}")
        generic[kind] += 1
        conns = cell["connections"]
        if kind.startswith(("$_DFF", "$_SDFF", "$_ADFF")):
            if len(conns.get("Q", ())) != 1 or len(conns.get("D", ())) != 1:
                raise ValueError(f"Unexpected register width in {top}: {kind}")
            reg_d[conns["Q"][0]] = conns["D"][0]
            continue
        inputs = [bit for port, bits in conns.items()
                  if cell["port_directions"][port] == "input" for bit in bits]
        outputs = [bit for port, bits in conns.items()
                   if cell["port_directions"][port] == "output" for bit in bits]
        if len(outputs) != 1 or any(len(bits) != 1 for bits in conns.values()):
            raise ValueError(f"Unexpected multi-bit generic cell in {top}: {kind}")
        if isinstance(outputs[0], int):
            drivers[outputs[0]] = inputs

    if any(bit not in reg_d for bit in state_bits):
        raise ValueError(f"{top}: round_state does not map to 128 registers")

    def measure_from(sources, targets):
        @lru_cache(maxsize=None)
        def depth(bit):
            if bit in sources:
                return 0
            if not isinstance(bit, int) or bit not in drivers:
                return -10000
            return 1 + max((depth(inbit) for inbit in drivers[bit]), default=-10000)

        answer = max(depth(reg_d[state_bits[index]]) for index in targets)
        if answer < 0:
            raise ValueError(f"{top}: no requested round_state feedback path found")
        return answer

    return {
        "cells": sum(generic.values()),
        "path_99_2": measure_from(frozenset((state_bits[99],)), (2,)),
        "any_feedback": measure_from(frozenset(state_bits), range(128)),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--yosys", default="yosys")
    parser.add_argument("--output", type=Path, default=ROOT / "build/rtl/aes-timing-structure")
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    version = subprocess.check_output([args.yosys, "-V"], text=True).strip()
    fast = synth(args.yosys, output, "mdm_aes128_fast", "fast")
    opt = synth(args.yosys, output, "mdm_aes128_balanced_timing", "balanced-opt")
    diff = opt["cells"] - fast["cells"]
    summary = (f"{version}\n"
               "Method: synth -noabc; check -assert; flatten; count generic cells and "
               "unit-weight Q-to-D topology (fast -> balanced-opt).\n"
               "NOT target cell area, mapped delay, STA, or physical timing.\n"
               f"Generic cells: {fast['cells']:,} -> {opt['cells']:,} "
               f"({diff:+,}, {diff * 100 / fast['cells']:+.2f}%)\n"
               f"round_state[99] Q to round_state[2] D: "
               f"{fast['path_99_2']} -> {opt['path_99_2']} generic levels\n"
               f"Longest round_state Q to round_state D: "
               f"{fast['any_feedback']} -> {opt['any_feedback']} generic levels\n"
               f"Full JSON and logs: {output}\n")
    (output / "summary.txt").write_text(summary, encoding="utf-8")
    print(summary, end="")


if __name__ == "__main__":
    try:
        main()
    except (KeyError, ValueError, OSError, subprocess.CalledProcessError, json.JSONDecodeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
