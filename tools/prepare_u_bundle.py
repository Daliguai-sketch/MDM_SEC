#!/usr/bin/env python3
"""Generate vectors outside U network and package a Make/Python-free VCS flow."""
import argparse
import gzip
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PACKAGE_NAME = "mdm_sec_u"
ARCHIVE_NAME = PACKAGE_NAME + ".tar.gz"

# All RTL and includes live in design/vc. The two-level filelist and both
# testbenches live in design/tb. No Makefile or Python sources go to U network.
RTL_FILES = (
    "mdm_aes_sbox.v", "mdm_aes_blocks.v", "mdm_aes_balanced_blocks.v", "mdm_aes128_serial.v",
    "mdm_aes128_fast.v", "mdm_aes128_balanced.v", "mdm_aes128.v", "mdm_snow3g.v", "mdm_zuc.v",
    "mdm_packet_buffer.v", "mdm_cipher.v", "mdm_integrity.v", "mdm_sec.v",
    "mdm_sboxes.vh", "mdm_aes_sbox.vh", "mdm_aes_mix_balanced.vh",
)
PACKAGE_FILES = {
    "docs/u_network_test.md": "README_U.md",
    "tools/u_network/run.sh": "design/tb/run.sh",
    "tools/u_network/filelist.f": "design/tb/filelist.f",
    "tools/u_network/filelist_aes.f": "design/tb/filelist_aes.f",
    "tools/u_network/mdm_sec_rtl.vc": "design/vc/mdm_sec_rtl.vc",
    "tests/rtl/tb_mdm_sec.sv": "design/tb/tb_mdm_sec.sv",
    "tests/rtl/tb_aes_random.sv": "design/tb/tb_aes_random.sv",
    **{f"rtl/{name}": f"design/vc/{name}" for name in RTL_FILES},
}
GENERATOR_FILES = (
    "tools/prepare_u_bundle.py",
    "tests/gen_vectors.py",
    "tests/gen_wave_vectors.py",
    "tests/gen_aes_vectors.py",
    "tests/reference_model.py",
    "sec_core/aes/sec_aes_core_enc.py",
    "sec_core/snow3g/sec_snow3g_core.py",
    "sec_core/zuc/sec_zuc_core.py",
)
SOURCE_FILES = tuple(sorted(set(PACKAGE_FILES) | set(GENERATOR_FILES) | {"rtl/files.f"}))


def source_snapshot():
    # Keep the external packaging step consistent if sources change while the
    # reference vectors are being generated; no transfer checksum is required.
    return {name: (ROOT / name).read_bytes() for name in SOURCE_FILES}


def check_rtl_filelist():
    """Prevent an out-of-date U-network list or copy map from dropping RTL."""
    original = (ROOT / "rtl/files.f").read_text()
    expected = original.replace("+incdir+rtl", "+incdir+../vc").replace("rtl/", "../vc/")
    actual = (ROOT / "tools/u_network/mdm_sec_rtl.vc").read_text()
    if actual != expected:
        raise RuntimeError("tools/u_network/mdm_sec_rtl.vc is out of sync with rtl/files.f")
    listed = {line[4:] for line in original.splitlines() if line.startswith("rtl/")}
    copied = {name for name in RTL_FILES if name.endswith(".v")}
    if listed != copied:
        raise RuntimeError("U-network RTL copy map does not match rtl/files.f")


def run_generator(script, output):
    env = os.environ.copy()
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    # Assertions in the generators check published answers; never suppress them.
    env.pop("PYTHONOPTIMIZE", None)
    result = subprocess.run([sys.executable, str(ROOT / script), str(output)],
                            cwd=ROOT, env=env, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    text = result.stdout.replace(str(output.parent) + os.sep, "vectors/")
    print(f"--- {script} ---\n{text}", end="" if text.endswith("\n") else "\n")
    if result.returncode:
        raise RuntimeError(f"{script} failed with exit code {result.returncode}")
    return f"--- {script} ---\n{text}"


def check_packet_vectors(path, max_bytes):
    """Validate record boundaries, counts and contiguous IDs before transfer."""
    count = 0
    with path.open(encoding="ascii") as source:
        while True:
            line = source.readline()
            if not line:
                break
            parts = line.split()
            if len(parts) != 17:
                raise RuntimeError(f"Bad packet descriptor {count} in {path}")
            try:
                case_id, a_len, b_len, output_len = map(
                    int, (parts[0], parts[9], parts[10], parts[13]))
            except ValueError as exc:
                raise RuntimeError(f"Non-numeric packet length or ID in {path}") from exc
            if case_id != count or min(a_len, b_len, output_len) < 0 or a_len + b_len > max_bytes:
                raise RuntimeError(f"Out-of-range or non-contiguous packet {case_id} in {path}")
            beats = (a_len + 15) // 16 + (b_len + 15) // 16 + (output_len + 15) // 16
            for _ in range(beats):
                word = source.readline().strip()
                if len(word) != 32 or any(c not in "0123456789abcdefABCDEF" for c in word):
                    raise RuntimeError(f"Truncated/invalid beat in packet {case_id} of {path}")
            count += 1
    return count


def normalized_tarinfo(info):
    # Do not expose the external machine's usernames or ownership in the archive.
    info.uid = 0
    info.gid = 0
    info.uname = ""
    info.gname = ""
    info.mtime = 0
    return info


def create_bundle(output_dir):
    output_dir.mkdir(parents=True, exist_ok=True)
    before = source_snapshot()
    check_rtl_filelist()
    with tempfile.TemporaryDirectory(prefix=".mdm-u-stage-", dir=output_dir) as work:
        workdir = Path(work)
        bundle = workdir / PACKAGE_NAME
        bundle.mkdir()
        for source_name, dest_name in PACKAGE_FILES.items():
            source = ROOT / source_name
            dest = bundle / dest_name
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, dest)
        (bundle / "design/tb/run.sh").chmod(0o755)

        vectors = bundle / "design/tb/vectors"
        vectors.mkdir()
        log = run_generator("tests/gen_vectors.py", vectors / "packet_vectors.txt")
        log += run_generator("tests/gen_wave_vectors.py", vectors / "wave_vectors.txt")
        log += run_generator("tests/gen_aes_vectors.py", vectors / "aes_vectors.txt")
        if source_snapshot() != before:
            raise RuntimeError("RTL, testbench or generator sources changed during packaging; retry")

        packet_count = check_packet_vectors(vectors / "packet_vectors.txt", 2048)
        wave_count = check_packet_vectors(vectors / "wave_vectors.txt", 512)
        case_count = len((vectors / "wave_vectors.cases.txt").read_text().splitlines())
        aes_lines = (vectors / "aes_vectors.txt").read_text().splitlines()
        if (packet_count, wave_count, case_count, len(aes_lines)) != (2641, 20, 20, 515):
            raise RuntimeError(f"Unexpected counts: packet={packet_count}, wave={wave_count}, "
                               f"case list={case_count}, AES={len(aes_lines)}")
        for line in aes_lines:
            words = line.split()
            if len(words) != 3 or any(len(word) != 32 or
                                      any(c not in "0123456789abcdefABCDEF" for c in word)
                                      for word in words):
                raise RuntimeError("Malformed AES input/expected-result vector")
        expected_fips = ("000102030405060708090a0b0c0d0e0f "
                         "00112233445566778899aabbccddeeff "
                         "69c4e0d86a7b0430d8cdb78070b4c55a")
        if aes_lines[0] != expected_fips:
            raise RuntimeError("First AES fixed-answer vector does not match FIPS-197")

        # Record the external generator names and log; the Python sources stay
        # outside the U network.
        provenance = ["Python vector generation (performed outside U network)",
                      f"Python version: {sys.version.split()[0]}",
                      f"Packet regression cases: {packet_count}; directed wave cases: {wave_count}; "
                      f"AES blocks: {len(aes_lines)}", "", log.rstrip(), "",
                      "External generator sources (not included):"]
        provenance += [f"  {name}" for name in sorted(GENERATOR_FILES)]
        (vectors / "generation_info.txt").write_text("\n".join(provenance) + "\n")

        # Normalize gzip and tar timestamps as well as tar ownership so the
        # same inputs and tool environment yield the same transfer archive.
        staged_archive = workdir / ARCHIVE_NAME
        with staged_archive.open("wb") as raw:
            with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0) as compressed:
                with tarfile.open(fileobj=compressed, mode="w") as archive:
                    archive.add(bundle, arcname=PACKAGE_NAME, filter=normalized_tarinfo)
        # Overwrite only our named output, never the caller's directory.
        final_archive = output_dir / ARCHIVE_NAME
        os.replace(staged_archive, final_archive)
    print(f"U-network package: {final_archive}")
    print("Contents: 2641 packet regression cases, 20 directed wave cases, "
          "515 AES blocks; no Makefile or Python sources")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", default="deliverables/u_transfer", metavar="DIR",
                        help="output directory (default: deliverables/u_transfer)")
    args = parser.parse_args()
    create_bundle(Path(args.output).expanduser().resolve())


if __name__ == "__main__":
    main()
