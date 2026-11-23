#!/usr/bin/env python3
"""Compare both 5-cycle AES implementations using the same Yosys flow.

Pre-ABC generic cells and unweighted topological path length are not physical
area, gate equivalents or timing. Full logs are retained under --output;
target-library PPA requires constraints and place/route. No source files change.
"""
import argparse
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
AES_RTL = (
    "rtl/mdm_aes_sbox.v", "rtl/mdm_aes_blocks.v", "rtl/mdm_aes_balanced_blocks.v",
    "rtl/mdm_aes128_serial.v", "rtl/mdm_aes128_fast.v", "rtl/mdm_aes128_balanced.v", "rtl/mdm_aes128.v",
)


def synth(yosys, output, label, variant):
    script = ("read_verilog -Irtl " + " ".join(AES_RTL) + "; "
              f"hierarchy -check -top mdm_aes128 -chparam AES_LOW_AREA {variant}; "
              "synth -top mdm_aes128 -noabc; check -assert; stat; flatten; ltp -noff")
    log_path = output / (label + ".log")
    result = subprocess.run([yosys, "-Q", "-T", "-p", script], cwd=ROOT,
                            text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, check=False)
    log_path.write_text(result.stdout, encoding="utf-8")
    matches = list(re.finditer(r"^\s*(?:(\d+)\s+cells|Number of cells:\s*(\d+))\s*$",
                               result.stdout, re.MULTILINE))
    path = re.search(r"^Longest topological path .*\(length=(\d+)\):",
                     result.stdout, re.MULTILINE)
    if result.returncode or not matches or not path or "Found and reported 0 problems." not in result.stdout:
        raise RuntimeError(f"Yosys synthesis/check/path analysis did not complete; see {log_path}")
    return int(matches[-1].group(1) or matches[-1].group(2)), int(path.group(1))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--yosys", default="yosys")
    parser.add_argument("--output", type=Path, default=ROOT / "build/rtl/aes-balanced-area")
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    version = subprocess.check_output([args.yosys, "-V"], text=True).strip()
    fast, fast_path = synth(args.yosys, output, "fast", 0)
    balanced, balanced_path = synth(args.yosys, output, "balanced", 2)
    summary = (f"{version}\n"
               "Method: synth -noabc; check -assert; stat; flatten; ltp -noff.\n"
               "Generic cells/path length, not physical area or STA.\n"
               f"Original 5-cycle fast AES: {fast:,}\n"
               f"Optimized 5-cycle AES:     {balanced:,}\n"
               f"Difference: {balanced-fast:+,} ({(balanced-fast)*100/fast:+.2f}%)\n"
               f"Unweighted longest topological path: {fast_path} -> {balanced_path}\n"
               f"Full logs: {output}\n")
    (output / "summary.txt").write_text(summary, encoding="utf-8")
    print(summary, end="")


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, subprocess.CalledProcessError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
