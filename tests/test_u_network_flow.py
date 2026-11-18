#!/usr/bin/env python3
"""Test the transfer bundle and air-gapped Make plumbing using fake VCS/Verdi.

No test here validates real Synopsys binaries, PLI, RTL simulation or FSDB.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile
import unittest

from test_vcs_fsdb_flow import FAKE_SIMV, FAKE_VCS, FAKE_VERDI

ROOT = Path(__file__).resolve().parents[1]

# A second, shell-only fake checks that the U-side Make flow can succeed even
# when Python is absent from PATH. Its text output is explicitly not real FSDB.
SHELL_VCS = r'''#!/bin/sh
set -eu
top=
prev=
for arg in "$@"; do
    if [ "$prev" = -top ]; then top=$arg; fi
    prev=$arg
done
[ "$top" = tb_mdm_sec ] || [ "$top" = tb_aes_random ]
printf '%s\n' "$top" > mock-top
mkdir -p simv.daidir
printf 'Shell mock compiler only; not VCS.\n' > vcs_compile.log
cat > simv <<'END_SIMV'
#!/bin/sh
set -eu
vector=
fsdb=
for arg in "$@"; do
    case "$arg" in
        +VECTORS=*) vector=${arg#*=} ;;
        +FSDB=*) fsdb=${arg#*=} ;;
    esac
done
[ -s "$vector" ] && [ -n "$fsdb" ]
printf 'MOCK OUTPUT: NOT A REAL FSDB\n' > "$fsdb"
if [ "$(cat mock-top)" = tb_mdm_sec ]; then
    printf 'DIRECTED configuration MAX_BYTES=512 AES_LOW_AREA=1\nPASS directed waveform cases: mock\nPASS 20 packet vectors (MAX_BYTES=512)\n' > sim.log
else
    printf 'PASS 8 AES blocks, 50-cycle latency/II, mock\n' > sim.log
fi
END_SIMV
chmod +x simv
'''


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


class UNetworkFlowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.generated = tempfile.TemporaryDirectory(prefix="mdm-u-generated-")
        cls.generated_dir = Path(cls.generated.name)
        result = subprocess.run(
            [sys.executable, str(ROOT / "tools/prepare_u_bundle.py"),
             "--output", str(cls.generated_dir)],
            cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        if result.returncode:
            cls.generated.cleanup()
            raise RuntimeError("Bundle generation failed:\n" + result.stdout)
        cls.generation_log = result.stdout
        cls.archive = cls.generated_dir / "mdm_sec_u.tar.gz"

    @classmethod
    def tearDownClass(cls):
        cls.generated.cleanup()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="mdm-u-test-")
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        subprocess.run(["tar", "-xzf", str(self.archive), "-C", str(self.home)], check=True)
        self.bundle = self.home / "mdm_sec_u"
        self.build = self.home / "sim-output"
        self.vcs_home = self.home / "vcs"
        self.verdi_home = self.home / "verdi"
        vcs = self.vcs_home / "bin/vcs"
        verdi = self.verdi_home / "bin/verdi"
        pli = self.verdi_home / "share/PLI/VCS/LINUX64"
        for directory in (vcs.parent, verdi.parent, pli):
            directory.mkdir(parents=True, exist_ok=True)
        for path, content in ((vcs, FAKE_VCS), (verdi, FAKE_VERDI)):
            path.write_text(content)
            path.chmod(0o755)
        (pli / "novas.tab").write_text("mock PLI table\n")
        (pli / "pli.a").write_text("mock library\n")
        self.python_marker = self.home / "python-called"
        self.forbidden_python = self.home / "forbidden-python"
        self.forbidden_python.write_text(f"#!/bin/sh\necho called > '{self.python_marker}'\nexit 99\n")
        self.forbidden_python.chmod(0o755)
        self.env = os.environ.copy()
        for key in ("VCS", "VERDI", "VCS_FLAGS", "VCS_EXTRA_FLAGS", "VCS_SIM_FLAGS",
                    "VERDI_PLI_DIR", "VERDI_TAB", "VERDI_PLI", "NOVAS_HOME", "BUILD_DIR",
                    "WAVE_DIR", "WAVE_AES_LOW_AREA", "WAVE_AES_BLOCKS", "WAVE_MAX_BYTES",
                    "FSDB_DIR", "FSDB_MDA", "FSDB_PREBUILT", "FSDB_VECTOR_DIR", "PYTHON",
                    "MOCK_SIM_RESULT", "MAKEFLAGS", "MFLAGS", "MAKELEVEL", "MAKEOVERRIDES"):
            self.env.pop(key, None)
        self.env.update(VCS_HOME=str(self.vcs_home), VERDI_HOME=str(self.verdi_home),
                        MOCK_SIMV_SCRIPT=FAKE_SIMV)

    def make(self, *args, ok=True):
        command = ["make", "--no-print-directory", "-f", "Makefile.u", *args,
                   f"BUILD_DIR={self.build}", f"PYTHON={self.forbidden_python}"]
        result = subprocess.run(command, cwd=self.bundle, env=self.env, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        if ok and result.returncode != 0:
            self.fail(f"{' '.join(command)} unexpectedly failed:\n{result.stdout}")
        if not ok and result.returncode == 0:
            self.fail(f"{' '.join(command)} unexpectedly succeeded:\n{result.stdout}")
        self.assertFalse(self.python_marker.exists(), "U Makefile invoked the Python generator")
        return result.stdout

    def test_package_checksums_contents_and_generation_log(self):
        checked = subprocess.run(["sha256sum", "-c", "mdm_sec_u.tar.gz.sha256"],
                                 cwd=self.generated_dir, text=True,
                                 stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.assertEqual(checked.returncode, 0, checked.stdout)
        with tarfile.open(self.archive, "r:gz") as archive:
            members = archive.getmembers()
        self.assertTrue(all(member.name == "mdm_sec_u" or member.name.startswith("mdm_sec_u/")
                            for member in members))
        self.assertTrue(all(member.isfile() or member.isdir() for member in members))
        self.assertFalse(any(member.name.endswith((".py", ".pyc")) for member in members))
        self.assertIn("20 directed packets, 515 AES blocks", self.generation_log)
        verified = self.make("verify-bundle")
        self.assertIn("Makefile.u: OK", verified)
        self.assertIn("vectors/wave_vectors.txt: OK", verified)
        vectors = self.bundle / "vectors"
        self.assertEqual(len((vectors / "wave_vectors.cases.txt").read_text().splitlines()), 20)
        self.assertEqual(len((vectors / "aes_vectors.txt").read_text().splitlines()), 515)
        self.assertIn("69c4e0d86a7b0430d8cdb78070b4c55a",
                      (vectors / "aes_vectors.txt").read_text().splitlines()[0])
        self.assertIn("External generator source SHA-256", (vectors / "generation_info.txt").read_text())
        self.assertFalse((self.bundle / "tests/gen_wave_vectors.py").exists())

    def test_offline_run_and_force_rebuild_use_only_transferred_inputs(self):
        vectors = self.bundle / "vectors"
        originals = {name: digest(vectors / name) for name in ("wave_vectors.txt", "aes_vectors.txt")}
        # Simulate old transferred timestamps relative to RTL/Makefile. -B and
        # hostile command-line overrides must not invoke a generator either.
        for name in originals:
            os.utime(vectors / name, (1, 1))
        options = ("FSDB_PREBUILT=0", "FSDB_VECTOR_DIR=/not/the/transferred/vectors",
                   "FSDB_PACKET_VECTOR=/not/packet.txt", "FSDB_AES_VECTOR=/not/aes.txt",
                   "FSDB_PACKET_VECTOR_DEPS=tests/gen_wave_vectors.py",
                   "FSDB_AES_VECTOR_DEPS=tests/gen_aes_vectors.py")
        out = self.make("fsdb", *options)
        self.assertIn("PASS packet self-check and nonempty FSDB", out)
        self.assertIn("PASS AES self-check and nonempty FSDB", out)
        # A newer stale simv must never be reused after transferring a bundle.
        for directory in ("vcs_packet_512_1", "vcs_aes_1"):
            simv = self.build / directory / "simv"
            simv.write_text("#!/bin/sh\necho STALE_SIMV_MUST_NOT_RUN\nexit 88\n")
            simv.chmod(0o755)
        out = self.make("fsdb", *options)
        self.assertNotIn("STALE_SIMV_MUST_NOT_RUN", out)
        self.make("-B", "fsdb", *options)
        for directory, name in (("vcs_packet_512_1", "wave_vectors.txt"),
                                ("vcs_aes_1", "aes_vectors.txt")):
            args = json.loads((self.build / directory / "run_args.json").read_text())
            self.assertIn("+VECTORS=" + str(vectors / name), args)
            self.assertEqual(digest(vectors / name), originals[name])
        self.make("verdi-packet")
        self.make("verdi-aes")

    def test_all_aes_blocks_option(self):
        out = self.make("fsdb-aes", "WAVE_AES_BLOCKS=515")
        args = json.loads((self.build / "vcs_aes_1/run_args.json").read_text())
        self.assertIn("+LIMIT=515", args)
        self.assertIn("PASS AES self-check and nonempty FSDB", out)

    def test_no_python_executable_on_u_network_path(self):
        path_dir = self.home / "isolated-path"
        path_dir.mkdir()
        for tool in ("sha256sum", "mkdir", "rm", "touch", "grep", "wc", "cat", "chmod", "echo"):
            executable = shutil.which(tool)
            self.assertIsNotNone(executable, tool)
            (path_dir / tool).symlink_to(executable)
        vcs = self.vcs_home / "bin/vcs"
        vcs.write_text(SHELL_VCS)
        vcs.chmod(0o755)
        env = self.env.copy()
        env["PATH"] = str(path_dir)
        self.assertNotEqual(subprocess.run(["/bin/sh", "-c", "command -v python3"],
                                           env=env, stdout=subprocess.DEVNULL).returncode, 0)
        command = [shutil.which("make"), "--no-print-directory", "-f", "Makefile.u", "-B", "fsdb",
                   f"BUILD_DIR={self.build}", f"PYTHON={self.forbidden_python}"]
        result = subprocess.run(command, cwd=self.bundle, env=env, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("PASS packet self-check and nonempty FSDB", result.stdout)
        self.assertIn("PASS AES self-check and nonempty FSDB", result.stdout)
        self.assertFalse(self.python_marker.exists())

    def test_missing_vector_fails_without_regeneration(self):
        path = self.bundle / "vectors/wave_vectors.txt"
        path.unlink()
        out = self.make("fsdb-packet", ok=False)
        self.assertIn("Packet vectors missing, unreadable or empty", out)
        self.assertFalse(path.exists())
        self.assertFalse((self.build / "vcs_packet_512_1/compile_args.json").exists())

    def test_corruption_fails_checksum_before_parallel_compilation(self):
        with (self.bundle / "vectors/aes_vectors.txt").open("a") as out:
            out.write("tampered\n")
        out = self.make("-j", "2", "fsdb", ok=False)
        self.assertIn("vectors/aes_vectors.txt: FAILED", out)
        self.assertFalse((self.build / "vcs_packet_512_1/compile_args.json").exists())
        self.assertFalse((self.build / "vcs_aes_1/compile_args.json").exists())

    def test_wrapper_blocks_python_and_destructive_goals(self):
        for goal in ("test", "wave", "clean"):
            self.assertIn("U-network package supports only", self.make(goal, ok=False))
        self.assertTrue((self.bundle / "vectors/wave_vectors.txt").exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
