#!/usr/bin/env python3
"""Reproduce the pre/post Yosys generic-cell comparison, without modifying RTL.

The baseline is the previous Git commit, or an extracted source snapshot passed
with --baseline-dir. Reports are generated under --output, never in source RTL.
These pre-ABC counts are NOT target-library cell area or timing estimates.
"""
import argparse
import io
import re
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[1]
BASELINE = "711947b1c08a16688d1521be45426868f4fd03e9"


def source_list(rtl):
    lines = (rtl / "files.f").read_text().splitlines()
    return [rtl / Path(line.strip()).name for line in lines
            if line.strip() and not line.strip().startswith(("+", "#"))]


def quote(path):
    return '"' + str(path).replace("\\", "\\\\").replace('"', '\\"') + '"'


def synth(yosys, output, name, rtl, sources, top, parameters):
    read = "read_verilog -I" + quote(rtl) + " " + " ".join(map(quote, sources))
    params = " ".join(f"-chparam {key} {value}" for key, value in parameters.items())
    script = (f"{read}; hierarchy -check -top {top} {params}; "
              f"synth -top {top} -noabc; check -assert; stat")
    log_path = output / f"{name}.log"
    print(f"Synthesizing {name} ...", flush=True)
    with log_path.open("w") as log:
        completed = subprocess.run([yosys, "-Q", "-T", "-p", script], cwd=ROOT,
                                   stdout=log, stderr=subprocess.STDOUT, check=False)
    text = log_path.read_text(errors="replace")
    if completed.returncode:
        print("\n".join(text.splitlines()[-30:]), file=sys.stderr)
        raise RuntimeError(f"Yosys failed; see {log_path}")
    matches = list(re.finditer(r"^\s*(?:(\d+)\s+cells|Number of cells:\s*(\d+))\s*$",
                               text, re.MULTILINE))
    if not matches or "Found and reported 0 problems." not in text:
        raise RuntimeError(f"missing stat/check in {log_path}")
    return int(matches[-1].group(1) or matches[-1].group(2))


def extract_baseline(ref, target):
    try:
        commit = subprocess.check_output(["git", "rev-parse", "--verify", ref + "^{commit}"],
                                         cwd=ROOT, text=True, stderr=subprocess.DEVNULL).strip()
        tar_bytes = subprocess.check_output(["git", "archive", commit, "rtl"], cwd=ROOT)
    except subprocess.CalledProcessError as exc:
        raise RuntimeError("Baseline Git commit unavailable. Fetch the branch history, or pass "
                           "--baseline-dir pointing to the extracted old snapshot.") from exc
    with tarfile.open(fileobj=io.BytesIO(tar_bytes), mode="r:") as archive:
        for member in archive.getmembers():
            path = PurePosixPath(member.name)
            if not member.isfile() or path.parts[0] != "rtl" or ".." in path.parts:
                continue
            dest = target.joinpath(*path.parts)
            dest.parent.mkdir(parents=True, exist_ok=True)
            with archive.extractfile(member) as src, dest.open("wb") as out:
                out.write(src.read())
    return commit, target / "rtl"


def compare(label, before, after):
    return f"{label:<34} {before:>9,} -> {after:>9,}   {(after-before)*100/before:+.2f}%"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--yosys", default="yosys", help="Yosys executable")
    parser.add_argument("--baseline", default=BASELINE, help="Git ref for original RTL")
    parser.add_argument("--baseline-dir", type=Path, help="old snapshot root or its rtl directory")
    parser.add_argument("--output", type=Path, default=ROOT / "build/rtl/area-compare")
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    version = subprocess.check_output([args.yosys, "-V"], text=True).strip()

    with tempfile.TemporaryDirectory(prefix="baseline-", dir=output) as tmp:
        if args.baseline_dir:
            base = args.baseline_dir.resolve()
            base_rtl = base / "rtl" if (base / "rtl").is_dir() else base
            baseline = str(base)
        else:
            baseline, base_rtl = extract_baseline(args.baseline, Path(tmp))
        rtl = ROOT / "rtl"
        old_sources = source_list(base_rtl)
        new_sources = source_list(rtl)
        old_aes = synth(args.yosys, output, "aes-before", base_rtl,
                        [base_rtl / "mdm_aes128.v"], "mdm_aes128", {})
        new_aes_files = [rtl / n for n in ("mdm_aes_sbox.v", "mdm_aes_blocks.v",
                         "mdm_aes128_serial.v", "mdm_aes128_fast.v", "mdm_aes128.v")]
        new_aes = synth(args.yosys, output, "aes-after", rtl, new_aes_files,
                        "mdm_aes128", {"AES_LOW_AREA": 1})
        old_input = synth(args.yosys, output, "buffer-before-input", base_rtl,
                          [base_rtl / "mdm_packet_buffer.v"], "mdm_packet_buffer",
                          {"CAP_BYTES": 2048, "READ_PORTS": 2})
        old_result = synth(args.yosys, output, "buffer-before-result", base_rtl,
                           [base_rtl / "mdm_packet_buffer.v"], "mdm_packet_buffer",
                           {"CAP_BYTES": 2052, "READ_PORTS": 1})
        new_input = synth(args.yosys, output, "buffer-after-address-only", rtl,
                          [rtl / "mdm_packet_buffer.v"], "mdm_packet_buffer",
                          {"CAP_BYTES": 2048, "READ_PORTS": 2})
        new_buffer = synth(args.yosys, output, "buffer-after-inplace", rtl,
                           [rtl / "mdm_packet_buffer.v"], "mdm_packet_buffer",
                           {"CAP_BYTES": 2052, "READ_PORTS": 2})
        old_top = synth(args.yosys, output, "top-before-2048", base_rtl, old_sources,
                        "mdm_sec", {"MAX_BYTES": 2048})
        new_top = synth(args.yosys, output, "top-after-2048", rtl, new_sources,
                        "mdm_sec", {"MAX_BYTES": 2048, "AES_LOW_AREA": 1})
        new_top_fast = synth(args.yosys, output, "top-after-2048-fast", rtl, new_sources,
                             "mdm_sec", {"MAX_BYTES": 2048, "AES_LOW_AREA": 0})

    lines = [
        version,
        f"Baseline: {baseline}",
        "Method: synth -noabc; check -assert; stat (generic cells, NOT physical area)",
        compare("One AES core", old_aes, new_aes),
        compare("Input buffer address change only", old_input, new_input),
        compare("Input + result buffer modules", old_input + old_result, new_buffer),
        f"  before input={old_input:,}, result={old_result:,}; after shared={new_buffer:,}",
        compare("Top 2048 bytes, low-area AES", old_top, new_top),
        compare("Top 2048 bytes, fast AES", old_top, new_top_fast),
        "Storage bits at MAX_BYTES=2048: 32,896 -> 16,512 (including bank padding)",
        f"Full reports: {output}",
    ]
    summary = "\n".join(lines) + "\n"
    (output / "summary.txt").write_text(summary)
    print(summary, end="")


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, subprocess.CalledProcessError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
