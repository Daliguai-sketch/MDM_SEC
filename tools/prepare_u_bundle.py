#!/usr/bin/env python3
"""Generate reference vectors outside the U network and package a Python-free VCS flow."""
import argparse
import hashlib
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

# This deliberately excludes the Python sources from the transferred package.
# The standard Makefile is included only behind the restricted Makefile.u.
PACKAGE_FILES = {
    "Makefile": "Makefile",
    "tools/Makefile.u": "Makefile.u",
    "docs/u_network_test.md": "README_U.md",
    "rtl/files.f": "rtl/files.f",
    "rtl/mdm_aes_sbox.v": "rtl/mdm_aes_sbox.v",
    "rtl/mdm_aes_blocks.v": "rtl/mdm_aes_blocks.v",
    "rtl/mdm_aes128_serial.v": "rtl/mdm_aes128_serial.v",
    "rtl/mdm_aes128_fast.v": "rtl/mdm_aes128_fast.v",
    "rtl/mdm_aes128.v": "rtl/mdm_aes128.v",
    "rtl/mdm_snow3g.v": "rtl/mdm_snow3g.v",
    "rtl/mdm_zuc.v": "rtl/mdm_zuc.v",
    "rtl/mdm_packet_buffer.v": "rtl/mdm_packet_buffer.v",
    "rtl/mdm_cipher.v": "rtl/mdm_cipher.v",
    "rtl/mdm_integrity.v": "rtl/mdm_integrity.v",
    "rtl/mdm_sec.v": "rtl/mdm_sec.v",
    "rtl/mdm_sboxes.vh": "rtl/mdm_sboxes.vh",
    "rtl/mdm_aes_sbox.vh": "rtl/mdm_aes_sbox.vh",
    "tests/rtl/tb_mdm_sec.sv": "tests/rtl/tb_mdm_sec.sv",
    "tests/rtl/tb_aes_random.sv": "tests/rtl/tb_aes_random.sv",
}
GENERATOR_FILES = (
    "tools/prepare_u_bundle.py",
    "tests/gen_wave_vectors.py",
    "tests/gen_aes_vectors.py",
    "tests/reference_model.py",
    "sec_core/aes/sec_aes_core_enc.py",
    "sec_core/snow3g/sec_snow3g_core.py",
    "sec_core/zuc/sec_zuc_core.py",
)


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def source_fingerprints():
    return {name: sha256(ROOT / name) for name in GENERATOR_FILES}


def run_generator(script, output):
    env = os.environ.copy()
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    # Assertions in the generators check published answers; never suppress them.
    env.pop("PYTHONOPTIMIZE", None)
    result = subprocess.run([sys.executable, str(ROOT / script), str(output)],
                            cwd=ROOT, env=env, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    text = result.stdout.replace(str(output.parent.parent) + os.sep, "")
    print(f"--- {script} ---\n{text}", end="" if text.endswith("\n") else "\n")
    if result.returncode:
        raise RuntimeError(f"{script} failed with exit code {result.returncode}")
    return f"--- {script} ---\n{text}"


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
    before = source_fingerprints()
    with tempfile.TemporaryDirectory(prefix=".mdm-u-stage-", dir=output_dir) as work:
        workdir = Path(work)
        bundle = workdir / PACKAGE_NAME
        bundle.mkdir()
        for source_name, dest_name in PACKAGE_FILES.items():
            source = ROOT / source_name
            dest = bundle / dest_name
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, dest)

        vectors = bundle / "vectors"
        vectors.mkdir()
        log = run_generator("tests/gen_wave_vectors.py", vectors / "wave_vectors.txt")
        log += run_generator("tests/gen_aes_vectors.py", vectors / "aes_vectors.txt")
        if source_fingerprints() != before:
            raise RuntimeError("Python generator sources changed during packaging; retry")
        packet_count = len((vectors / "wave_vectors.cases.txt").read_text().splitlines())
        aes_count = len((vectors / "aes_vectors.txt").read_text().splitlines())
        if (packet_count, aes_count) != (20, 515):
            raise RuntimeError(f"Unexpected vector counts: packet={packet_count}, AES={aes_count}")
        expected_fips = ("000102030405060708090a0b0c0d0e0f "
                         "00112233445566778899aabbccddeeff "
                         "69c4e0d86a7b0430d8cdb78070b4c55a")
        if (vectors / "aes_vectors.txt").read_text().splitlines()[0] != expected_fips:
            raise RuntimeError("First AES fixed-answer vector does not match FIPS-197")

        # Input-source hashes are informational: the sources themselves stay
        # outside the U network. SHA256SUMS below checks transferred files.
        provenance = ["Python vector generation (performed outside U network)",
                      f"Python version: {sys.version.split()[0]}",
                      f"Packet cases: {packet_count}; AES blocks: {aes_count}",
                      "", log.rstrip(), "",
                      "External generator source SHA-256 (informational):"]
        provenance += [f"{digest}  {name}" for name, digest in sorted(before.items())]
        (vectors / "generation_info.txt").write_text("\n".join(provenance) + "\n")

        files = sorted(path for path in bundle.rglob("*") if path.is_file())
        manifest = "".join(f"{sha256(path)}  {path.relative_to(bundle).as_posix()}\n"
                           for path in files)
        (bundle / "SHA256SUMS").write_text(manifest)

        staged_archive = workdir / ARCHIVE_NAME
        with tarfile.open(staged_archive, "w:gz") as archive:
            archive.add(bundle, arcname=PACKAGE_NAME, filter=normalized_tarinfo)
        staged_checksum = workdir / (ARCHIVE_NAME + ".sha256")
        staged_checksum.write_text(f"{sha256(staged_archive)}  {ARCHIVE_NAME}\n")
        # Overwrite only our two named outputs, never the caller's directory.
        final_archive = output_dir / ARCHIVE_NAME
        final_checksum = output_dir / (ARCHIVE_NAME + ".sha256")
        os.replace(staged_archive, final_archive)
        os.replace(staged_checksum, final_checksum)
    print(f"U-network package: {final_archive}")
    print(f"Transfer checksum:  {final_checksum}")
    print("Contents: 20 directed packets, 515 AES blocks, RTL, testbenches and no Python sources")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", default="deliverables/u_transfer", metavar="DIR",
                        help="output directory (default: deliverables/u_transfer)")
    args = parser.parse_args()
    create_bundle(Path(args.output).expanduser().resolve())


if __name__ == "__main__":
    main()
