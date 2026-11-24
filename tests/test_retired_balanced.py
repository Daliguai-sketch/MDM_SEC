#!/usr/bin/env python3
"""Verify the retired balanced-core parameter is rejected at elaboration.

This uses the real Verilator frontend, not mocks. The legacy guard remains
accepted for fast/serial, where it never selected a balanced implementation.
"""
import argparse
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
RETIRED = "MDM_ERROR_ORIGINAL_BALANCED_REMOVED_SET_BALANCED_TIMING_OPT_TO_1"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verilator", required=True)
    args = parser.parse_args()
    sources = [line for line in (ROOT / "rtl/files.f").read_text().splitlines()
               if line.startswith("rtl/") and line.endswith(".v")]
    cases = (
        ("standalone balanced-opt default", "mdm_aes128", ("AES_LOW_AREA=2",), True),
        ("standalone balanced-opt explicit", "mdm_aes128", ("AES_LOW_AREA=2", "BALANCED_TIMING_OPT=1"), True),
        ("removed standalone balanced", "mdm_aes128", ("AES_LOW_AREA=2", "BALANCED_TIMING_OPT=0"), False),
        ("legacy fast no-op", "mdm_aes128", ("AES_LOW_AREA=0", "BALANCED_TIMING_OPT=0"), True),
        ("legacy serial no-op", "mdm_aes128", ("AES_LOW_AREA=1", "BALANCED_TIMING_OPT=0"), True),
        ("both top-level balanced-opt lanes", "mdm_sec", ("AES_LOW_AREA=2",), True),
        ("explicit top-level balanced-opt", "mdm_sec", ("AES_LOW_AREA=2", "AES_INTEGRITY_TIMING_OPT=1"), True),
        ("removed direct integrity fallback", "mdm_integrity", ("AES_LOW_AREA=2", "BALANCED_TIMING_OPT=0"), False),
        ("removed top integrity fallback", "mdm_sec", ("AES_LOW_AREA=2", "AES_INTEGRITY_TIMING_OPT=0"), False),
        ("legacy top fast no-op", "mdm_sec", ("AES_LOW_AREA=0", "AES_INTEGRITY_TIMING_OPT=0"), True),
        ("legacy top serial no-op", "mdm_sec", ("AES_LOW_AREA=1", "AES_INTEGRITY_TIMING_OPT=0"), True),
    )
    for label, top, params, valid in cases:
        cmd = [args.verilator, "--language", "1364-2005", "--lint-only", "-Irtl",
               "--top-module", top, *("-G" + p for p in params), *sources]
        result = subprocess.run(cmd, cwd=ROOT, text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, check=False)
        if (result.returncode == 0) != valid or (not valid and RETIRED not in result.stdout):
            raise RuntimeError(f"{label}: unexpected status {result.returncode}\n{result.stdout}")
        print(f"PASS {label}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
