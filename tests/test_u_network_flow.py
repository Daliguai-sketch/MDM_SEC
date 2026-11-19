#!/usr/bin/env python3
"""Test the U-network script without Make/Python, using shell-only fake tools.

These fakes do not run RTL or generate real FSDB and cannot validate VCS/PLI
or the real VCS toolchain's own dependencies.
"""
import importlib.util
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

# The mock executable is intentionally POSIX shell, so the simulated U network
# can have neither Python nor Make in PATH. Its FSDB output is plain text.
SHELL_VCS = r'''#!/bin/sh
set -eu
printf '%s\n' "$@" > compile_args.txt
if [ "${MOCK_COMPILE_FAIL:-0}" = 1 ]; then exit 17; fi
top= filelist= log= variant= size= tab= pli= prev= pli_next=0 macro=0
for arg in "$@"; do
    if [ "$prev" = -top ]; then top=$arg; fi
    if [ "$prev" = -f ]; then filelist=$arg; fi
    if [ "$prev" = -l ]; then log=$arg; fi
    if [ "$prev" = -P ]; then tab=$arg; pli_next=1
    elif [ "$pli_next" = 1 ]; then pli=$arg; pli_next=0; fi
    case "$arg" in
        +define+MDM_SEC_FSDB) macro=1 ;;
        -pvalue+tb_mdm_sec.TEST_MAX_BYTES=*) size=${arg#*=} ;;
        -pvalue+tb_mdm_sec.TEST_AES_LOW_AREA=*) variant=${arg#*=} ;;
        -pvalue+tb_aes_random.TEST_AES_LOW_AREA=*) variant=${arg#*=} ;;
    esac
    prev=$arg
done
[ -n "$log" ] && [ -r "$filelist" ] && [ -r "$tab" ] && [ -r "$pli" ]
[ "$macro" = 1 ] && { [ "$variant" = 0 ] || [ "$variant" = 1 ]; }
case "$top" in
    tb_mdm_sec) tb=tb_mdm_sec.sv; [ "$size" = 2048 ] ;;
    tb_aes_random) tb=tb_aes_random.sv ;;
    *) exit 18 ;;
esac
# Resolve exactly the same relative entries used by the real filelist.
grep -Fx -- '-f ../vc/mdm_sec_rtl.vc' "$filelist" >/dev/null
grep -Fx -- "$tb" "$filelist" >/dev/null
[ -r "$tb" ] && [ -r ../vc/mdm_sec_rtl.vc ]
while IFS= read -r entry; do
    case "$entry" in
        +incdir+*) [ -d "${entry#+incdir+}" ] ;;
        ../vc/*.v) [ -r "$entry" ] ;;
        '') ;;
        *) echo "bad RTL filelist entry: $entry" >&2; exit 19 ;;
    esac
done < ../vc/mdm_sec_rtl.vc
[ -r ../vc/mdm_sboxes.vh ] && [ -r ../vc/mdm_aes_sbox.vh ]
printf '%s\n' "$top" > mock_top
printf '%s\n' "$variant" > mock_variant
mkdir -p simv.daidir
printf 'MOCK VCS COMPILER ONLY; NO RTL WAS COMPILED\n' > "$log"
cat > simv <<'END_SIMV'
#!/bin/sh
set -eu
vector= fsdb= log= limit= prev= directed=0 parallel=0 mda=0
for arg in "$@"; do
    if [ "$prev" = -l ]; then log=$arg; fi
    case "$arg" in
        +VECTORS=*) vector=${arg#*=} ;;
        +FSDB=*) fsdb=${arg#*=} ;;
        +LIMIT=*) limit=${arg#*=} ;;
        +DIRECTED_COVERAGE) directed=1 ;;
        +REQUIRE_PARALLEL_COVERAGE) parallel=1 ;;
        +FSDB_MDA) mda=1 ;;
    esac
    prev=$arg
done
[ -n "$log" ] && [ -s "$vector" ]
case "$vector" in
    */packet_vectors.txt) kind=regression ;;
    */wave_vectors.txt) kind=wave ;;
    */aes_vectors.txt) kind=aes ;;
    *) exit 20 ;;
esac
printf '%s\n' "$@" > "$kind.args"
if [ "${MOCK_RUN_FAIL:-}" = "$kind" ]; then exit 29; fi
top=$(cat mock_top)
variant=$(cat mock_variant)
if [ "${MOCK_WRONG_VARIANT:-0}" = 1 ]; then
    if [ "$variant" = 0 ]; then variant=1; else variant=0; fi
fi
case "$kind" in
    regression)
        [ "$top" = tb_mdm_sec ] && [ "$parallel" = 1 ]
        printf 'PASS simultaneous transfers by mode 2/3/4/5: mock\nPASS 2641 packet vectors (MAX_BYTES=2048), mock\n' > "$log"
        ;;
    wave)
        [ "$top" = tb_mdm_sec ] && [ "$directed" = 1 ] && [ -n "$fsdb" ]
        printf 'DIRECTED configuration MAX_BYTES=2048 AES_LOW_AREA=%s\nPASS directed waveform cases: mock\nPASS 20 packet vectors (MAX_BYTES=2048), mock\n' "$variant" > "$log"
        ;;
    aes)
        [ "$top" = tb_aes_random ] && [ -n "$limit" ] && [ -n "$fsdb" ]
        if [ "$variant" = 1 ]; then cycles=50; else cycles=5; fi
        printf 'PASS %s AES blocks, %s-cycle latency/II, mock\n' "$limit" "$cycles" > "$log"
        ;;
esac
if [ "${MOCK_BAD_LOG:-}" = "$kind" ]; then printf 'mock failure, no PASS\n' > "$log"; fi
if [ -n "$fsdb" ] && [ "${MOCK_MISSING_WAVE:-0}" != 1 ] && [ "${MOCK_MISSING_WAVE:-0}" != "$kind" ]; then
    printf 'MOCK OUTPUT: NOT A REAL FSDB\n' > "$fsdb"
fi
END_SIMV
chmod +x simv
'''


def write_executable(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)
    path.chmod(0o755)


class UNetworkFlowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.generated = tempfile.TemporaryDirectory(prefix="mdm-u-generated-")
        cls.generated_dir = Path(cls.generated.name)
        result = subprocess.run(
            [sys.executable, str(ROOT / "tools/prepare_u_bundle.py"),
             "--output", str(cls.generated_dir)], cwd=ROOT, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
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
        self.design = self.bundle / "design"
        self.tb = self.design / "tb"
        self.runner = self.tb / "run.sh"
        self.vcs = self.home / "tools/vcs"
        write_executable(self.vcs, SHELL_VCS)
        self.verdi_home = self.home / "verdi"
        self.pli = self.verdi_home / "share/PLI/VCS/LINUX64"
        self.pli.mkdir(parents=True)
        (self.pli / "novas.tab").write_text("mock table\n")
        (self.pli / "pli.a").write_text("mock library\n")
        self.env = os.environ.copy()
        for key in ("VCS", "VCS_HOME", "VERDI_HOME", "NOVAS_HOME", "VERDI_PLI_DIR",
                    "VERDI_TAB", "VERDI_PLI", "BSUB_CMD", "RUN_ROOT", "AES_LOW_AREA",
                    "RUN_FULL", "RUN_AES", "AES_BLOCKS", "FSDB_FULL", "FSDB_MDA", "VCS_EXTRA_FLAGS",
                    "MOCK_COMPILE_FAIL", "MOCK_RUN_FAIL", "MOCK_BAD_LOG",
                    "MOCK_WRONG_VARIANT", "MOCK_MISSING_WAVE"):
            self.env.pop(key, None)
        self.env.update(VCS=str(self.vcs), VERDI_HOME=str(self.verdi_home), BSUB_CMD="")

    def run_script(self, *args, updates=None, ok=True, cwd=None):
        env = self.env.copy()
        if updates:
            for key, value in updates.items():
                if value is None:
                    env.pop(key, None)
                else:
                    env[key] = str(value)
        result = subprocess.run([str(self.runner), *args], cwd=cwd or self.home,
                                env=env, text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT)
        if ok and result.returncode != 0:
            self.fail("run.sh unexpectedly failed:\n" + result.stdout)
        if not ok and result.returncode == 0:
            self.fail("run.sh unexpectedly succeeded:\n" + result.stdout)
        return result

    @staticmethod
    def run_dir(result):
        match = re.search(r"^Fresh output directory: (.+)$", result.stdout, re.MULTILINE)
        if not match:
            raise AssertionError("No fresh output directory in:\n" + result.stdout)
        return Path(match.group(1))

    def test_package_structure_filelists_and_counts(self):
        self.assertFalse((self.generated_dir / "mdm_sec_u.tar.gz.sha256").exists())
        with tarfile.open(self.archive, "r:gz") as archive:
            members = archive.getmembers()
        self.assertTrue(all(m.name == "mdm_sec_u" or m.name.startswith("mdm_sec_u/") for m in members))
        self.assertTrue(all(m.isfile() or m.isdir() for m in members))
        self.assertFalse(any(Path(m.name).name.startswith("Makefile") or
                             m.name.endswith((".py", ".pyc", "SHA256SUMS", ".sha256")) for m in members))
        self.assertFalse(any(m.name.endswith((".fsdb", ".vcd", "/simv")) or "/runs/" in m.name
                             for m in members), "no generated or fake waves/build products in transfer")
        script = next(m for m in members if m.name.endswith("/tb/run.sh"))
        self.assertTrue(script.mode & 0o111, "run.sh must be directly executable")
        self.assertEqual((self.tb / "filelist.f").read_text(),
                         "-f ../vc/mdm_sec_rtl.vc\ntb_mdm_sec.sv\n")
        self.assertEqual((self.tb / "filelist_aes.f").read_text(),
                         "-f ../vc/mdm_sec_rtl.vc\ntb_aes_random.sv\n")
        expected_vc = (ROOT / "rtl/files.f").read_text().replace("+incdir+rtl", "+incdir+../vc")
        expected_vc = expected_vc.replace("rtl/", "../vc/")
        self.assertEqual((self.design / "vc/mdm_sec_rtl.vc").read_text(), expected_vc)
        check = self.run_script("--check-files")
        self.assertIn("PASS required files present; contents not checked", check.stdout)
        self.assertFalse((self.tb / "runs").exists(), "file check must not invoke VCS")
        vectors = self.tb / "vectors"
        self.assertEqual(len((vectors / "wave_vectors.cases.txt").read_text().splitlines()), 20)
        self.assertEqual(len((vectors / "aes_vectors.txt").read_text().splitlines()), 515)
        self.assertIn("Packet regression cases: 2641; directed wave cases: 20; AES blocks: 515",
                      (vectors / "generation_info.txt").read_text())
        self.assertIn("2641 packet regression cases, 20 directed wave cases", self.generation_log)

    def test_packager_detects_rtl_filelist_and_copy_map_drift(self):
        spec = importlib.util.spec_from_file_location("bundle_tool", ROOT / "tools/prepare_u_bundle.py")
        bundle_tool = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(bundle_tool)
        fake = self.home / "source-copy"
        (fake / "rtl").mkdir(parents=True)
        (fake / "tools/u_network").mkdir(parents=True)
        original = (ROOT / "rtl/files.f").read_text()
        u_list = (ROOT / "tools/u_network/mdm_sec_rtl.vc").read_text()
        source = fake / "rtl/files.f"
        target = fake / "tools/u_network/mdm_sec_rtl.vc"
        source.write_text(original)
        target.write_text(u_list)
        bundle_tool.ROOT = fake
        bundle_tool.check_rtl_filelist()
        target.write_text(u_list + "../vc/new_rtl.v\n")
        with self.assertRaisesRegex(RuntimeError, "out of sync"):
            bundle_tool.check_rtl_filelist()
        source.write_text(original + "rtl/new_rtl.v\n")
        with self.assertRaisesRegex(RuntimeError, "copy map does not match"):
            bundle_tool.check_rtl_filelist()

    def test_archive_is_reproducible_and_does_not_remove_other_files(self):
        other = self.home / "regenerated"
        other.mkdir()
        sentinel = other / "keep-this.txt"
        sentinel.write_text("do not delete\n")
        result = subprocess.run([sys.executable, str(ROOT / "tools/prepare_u_bundle.py"),
                                 "--output", str(other)], cwd=ROOT, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual((other / "mdm_sec_u.tar.gz").read_bytes(), self.archive.read_bytes())
        self.assertEqual(sentinel.read_text(), "do not delete\n")

    def test_vectors_match_without_optional_pycryptodome(self):
        stub = self.home / "without-crypto/Crypto"
        stub.mkdir(parents=True)
        (stub / "__init__.py").write_text("raise ImportError('disabled by offline-flow test')\n")
        env = os.environ.copy()
        env["PYTHONPATH"] = str(stub.parent)
        other = self.home / "no-crypto-package"
        result = subprocess.run([sys.executable, str(ROOT / "tools/prepare_u_bundle.py"),
                                 "--output", str(other)], cwd=ROOT, env=env, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("independent AES cross-check skipped", result.stdout)
        self.assertIn("independent AES block cross-check skipped", result.stdout)
        with tarfile.open(self.archive, "r:gz") as checked, \
             tarfile.open(other / "mdm_sec_u.tar.gz", "r:gz") as unchecked:
            for name in ("packet_vectors.txt", "wave_vectors.txt", "wave_vectors.cases.txt", "aes_vectors.txt"):
                member = "mdm_sec_u/design/tb/vectors/" + name
                self.assertEqual(checked.extractfile(member).read(), unchecked.extractfile(member).read(), name)

    def test_default_full_regression_and_wave_from_arbitrary_cwd(self):
        result = self.run_script()
        run = self.run_dir(result)
        packet = run / "tb"
        self.assertTrue((run / "vc").is_symlink())
        self.assertTrue((packet / "tb_mdm_sec.sv").is_symlink())
        self.assertIn("PASS 2641 packet vectors", (packet / "regression.log").read_text())
        self.assertIn("PASS 20 packet vectors", (packet / "sim.log").read_text())
        self.assertEqual((packet / "waves.fsdb").read_text(), "MOCK OUTPUT: NOT A REAL FSDB\n")
        args = (packet / "compile_args.txt").read_text().splitlines()
        self.assertIn(str(self.tb / "filelist.f"), args)
        self.assertIn("+define+MDM_SEC_FSDB", args)
        self.assertIn("-pvalue+tb_mdm_sec.TEST_MAX_BYTES=2048", args)
        self.assertIn("-pvalue+tb_mdm_sec.TEST_AES_LOW_AREA=1", args)
        regression = (packet / "regression.args").read_text().splitlines()
        wave = (packet / "wave.args").read_text().splitlines()
        self.assertIn("+VECTORS=" + str(self.tb / "vectors/packet_vectors.txt"), regression)
        self.assertIn("+REQUIRE_PARALLEL_COVERAGE", regression)
        self.assertIn("+VECTORS=" + str(self.tb / "vectors/wave_vectors.txt"), wave)
        self.assertIn("+FSDB=" + str(packet / "waves.fsdb"), wave)
        self.assertIn("+fsdb+autoflush", wave)
        self.assertNotIn("+FSDB_MDA", wave)
        self.assertIn("PASS: packet self-check", result.stdout)
        self.assertEqual((run / "packet_regression.status").read_text(), "0\n")
        self.assertIn("+LIMIT=8", (run / "aes/aes.args").read_text().splitlines())
        self.assertIn("PASS 8 AES blocks, 50-cycle latency/II", (run / "aes/sim.log").read_text())
        self.assertEqual((run / "aes/aes_waves.fsdb").read_text(), "MOCK OUTPUT: NOT A REAL FSDB\n")
        self.assertIn("PASS: 8 AES blocks", result.stdout)

    def test_unique_runs_never_reuse_stale_simv_or_wave(self):
        first = self.run_dir(self.run_script())
        write_executable(first / "tb/simv", "#!/bin/sh\necho STALE_SIMV_MUST_NOT_RUN\nexit 88\n")
        old_wave = first / "tb/waves.fsdb"
        old_contents = old_wave.read_bytes()
        second_result = self.run_script()
        second = self.run_dir(second_result)
        self.assertNotEqual(first, second)
        self.assertNotIn("STALE_SIMV_MUST_NOT_RUN", second_result.stdout)
        self.assertEqual(old_wave.read_bytes(), old_contents)
        self.assertTrue((second / "tb/waves.fsdb").is_file())

    def test_fast_mda_and_all_aes_optional(self):
        result = self.run_script(updates={"AES_LOW_AREA": "0", "RUN_FULL": "0", "RUN_AES": "1",
                                          "AES_BLOCKS": "515", "FSDB_MDA": "1"})
        run = self.run_dir(result)
        self.assertIn("Skipping full packet regression", result.stdout)
        self.assertFalse((run / "tb/regression.log").exists())
        self.assertIn("+FSDB_MDA", (run / "tb/wave.args").read_text().splitlines())
        self.assertIn("-pvalue+tb_mdm_sec.TEST_AES_LOW_AREA=0",
                      (run / "tb/compile_args.txt").read_text().splitlines())
        self.assertIn(str(self.tb / "filelist_aes.f"),
                      (run / "aes/compile_args.txt").read_text().splitlines())
        self.assertIn("+LIMIT=515", (run / "aes/aes.args").read_text().splitlines())
        self.assertIn("PASS 515 AES blocks, 5-cycle latency/II", (run / "aes/sim.log").read_text())
        self.assertIn("NOT A REAL FSDB", (run / "aes/aes_waves.fsdb").read_text())

    def test_full_regression_fsdb_option_and_missing_wave(self):
        result = self.run_script(updates={"RUN_AES": "0", "FSDB_FULL": "1", "FSDB_MDA": "1"})
        run = self.run_dir(result)
        packet = run / "tb"
        args = (packet / "regression.args").read_text().splitlines()
        self.assertIn("+FSDB=" + str(packet / "regression.fsdb"), args)
        self.assertIn("+FSDB_MDA", args)
        self.assertIn("+CASE_LOG", args)
        self.assertEqual((packet / "regression.fsdb").read_text(), "MOCK OUTPUT: NOT A REAL FSDB\n")
        self.assertFalse((run / "aes").exists())
        self.assertIn("Regression FSDB:", result.stdout)
        result = self.run_script(updates={"RUN_AES": "0", "FSDB_FULL": "1",
                                          "MOCK_MISSING_WAVE": "regression"}, ok=False)
        self.assertIn("regression.fsdb is missing or empty", result.stdout)

    def test_relative_tool_paths_are_resolved_before_chdir(self):
        launcher = self.home / "launcher/submit"
        write_executable(launcher, "#!/bin/sh\nexec \"$@\"\n")
        result = self.run_script(updates={
            "VCS": "tools/vcs", "VERDI_HOME": None,
            "VERDI_TAB": "verdi/share/PLI/VCS/LINUX64/novas.tab",
            "VERDI_PLI": "verdi/share/PLI/VCS/LINUX64/pli.a",
            "BSUB_CMD": "launcher/submit", "RUN_ROOT": "output",
            "RUN_FULL": "0", "RUN_AES": "0", "VCS_EXTRA_FLAGS": "+mock_flag",
        }, cwd=self.home)
        run = self.run_dir(result)
        self.assertEqual(run.parent, self.home / "output")
        args = (run / "tb/compile_args.txt").read_text().splitlines()
        self.assertIn("+mock_flag", args)
        self.assertEqual(args[args.index("-P") + 1:args.index("-P") + 3],
                         [str(self.pli / "novas.tab"), str(self.pli / "pli.a")])
        self.assertIn("Blocking launcher: " + str(launcher), result.stdout)

    def test_synchronous_and_asynchronous_bsub_wrapper(self):
        launcher = self.home / "launcher"
        log = self.home / "launches.log"
        wrapper = launcher / "bsub_cmd"
        write_executable(wrapper, "#!/bin/sh\nprintf 'called\\n' >> \"$MOCK_LAUNCH_LOG\"\n\"$@\"\n")
        updates = {"PATH": str(launcher) + os.pathsep + self.env["PATH"],
                   "BSUB_CMD": None, "MOCK_LAUNCH_LOG": str(log)}
        result = self.run_script(updates=updates)
        self.assertIn("Blocking launcher: " + str(wrapper), result.stdout)
        self.assertEqual(log.read_text().splitlines(), ["called"] * 5)
        write_executable(wrapper, "#!/bin/sh\n# Simulate a submit-only wrapper, never executing the job.\nexit 0\n")
        failed = self.run_script(updates=updates, ok=False)
        self.assertIn("returned before the actual job finished", failed.stdout)
        self.assertFalse((self.run_dir(failed) / "tb/simv").exists())
        # Even a blocking wrapper that incorrectly masks the job exit code
        # cannot turn a failed VCS command into a successful invocation.
        write_executable(wrapper, "#!/bin/sh\n\"$@\"\nexit 0\n")
        failed = self.run_script(updates={**updates, "MOCK_COMPILE_FAIL": "1"}, ok=False)
        self.assertIn("compile job failed", failed.stdout)
        self.assertEqual((self.run_dir(failed) / "compile.status").read_text(), "17\n")
        # Some sites define bsub_cmd as a Bash function rather than a file.
        function_log = self.home / "function-launches.log"
        env = self.env.copy()
        env.pop("BSUB_CMD", None)
        env["MOCK_LAUNCH_LOG"] = str(function_log)
        bootstrap = ('bsub_cmd() { printf "called\\n" >> "$MOCK_LAUNCH_LOG"; "$@"; }; '
                     'export -f bsub_cmd; exec "$1"')
        result = subprocess.run(["bash", "-c", bootstrap, "bash", str(self.runner)],
                                cwd=self.home, env=env, text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("Blocking launcher: bsub_cmd", result.stdout)
        self.assertEqual(function_log.read_text().splitlines(), ["called"] * 5)

    def test_no_python_or_make_on_u_network_path(self):
        isolated = self.home / "isolated-path"
        isolated.mkdir()
        for tool in ("bash", "dirname", "mkdir", "mktemp", "ln", "grep", "cat", "chmod"):
            executable = shutil.which(tool)
            self.assertIsNotNone(executable, tool)
            (isolated / tool).symlink_to(executable)
        for forbidden in ("python", "python3", "make", "sha256sum"):
            self.assertNotEqual(subprocess.run(["/bin/sh", "-c", f"command -v {forbidden}"],
                                               env={"PATH": str(isolated)},
                                               stdout=subprocess.DEVNULL).returncode, 0)
        result = self.run_script(updates={"PATH": str(isolated), "RUN_AES": "1", "AES_BLOCKS": "8"})
        run = self.run_dir(result)
        self.assertIn("PASS 2641 packet vectors", (run / "tb/regression.log").read_text())
        self.assertIn("PASS 8 AES blocks", (run / "aes/sim.log").read_text())

    def test_missing_or_empty_inputs_fail_before_vcs(self):
        for path in (self.tb / "vectors/packet_vectors.txt", self.tb / "vectors/wave_vectors.txt",
                     self.tb / "tb_aes_random.sv", self.design / "vc/mdm_sec.v",
                     self.design / "vc/mdm_aes_sbox.vh"):
            with self.subTest(path=path):
                original = path.read_bytes()
                path.unlink()
                result = self.run_script(ok=False)
                self.assertIn("Required file missing, unreadable or empty", result.stdout)
                self.assertIn(str(path), result.stdout)
                self.assertFalse((self.tb / "runs").exists())
                path.write_bytes(b"")
                result = self.run_script("--check-files", ok=False)
                self.assertIn("Required file missing, unreadable or empty", result.stdout)
                path.write_bytes(original)
        # Presence checks intentionally do not validate a file's content.
        with (self.tb / "vectors/wave_vectors.txt").open("a") as dest:
            dest.write("modified\n")
        self.assertIn("contents not checked", self.run_script("--check-files").stdout)

    def test_disabled_suites_do_not_require_their_inputs(self):
        for path in (self.tb / "vectors/packet_vectors.txt", self.tb / "vectors/aes_vectors.txt",
                     self.tb / "tb_aes_random.sv", self.tb / "filelist_aes.f"):
            path.unlink()
        env = {"RUN_FULL": "0", "RUN_AES": "0"}
        self.assertIn("PASS required files", self.run_script("--check-files", updates=env).stdout)
        run = self.run_dir(self.run_script(updates=env))
        self.assertIn("PASS 20 packet vectors", (run / "tb/sim.log").read_text())
        self.assertFalse((run / "aes").exists())

    def test_compile_simulation_log_and_fsdb_fail_closed(self):
        for env, message in (
            ({"MOCK_COMPILE_FAIL": "1"}, "compile command failed"),
            ({"MOCK_RUN_FAIL": "regression"}, "packet_regression command failed"),
            ({"MOCK_RUN_FAIL": "wave"}, "packet_wave command failed"),
            ({"MOCK_BAD_LOG": "wave"}, "Packet testbench parameter mismatch"),
            ({"MOCK_MISSING_WAVE": "wave"}, "waves.fsdb is missing or empty"),
            ({"MOCK_WRONG_VARIANT": "1"}, "Packet testbench parameter mismatch"),
            ({"MOCK_RUN_FAIL": "aes"}, "aes_regression command failed"),
            ({"MOCK_BAD_LOG": "aes"}, "AES self-check/parameter mismatch"),
            ({"MOCK_MISSING_WAVE": "aes"}, "AES FSDB is missing or empty"),
        ):
            with self.subTest(env=env):
                result = self.run_script(updates=env, ok=False)
                self.assertIn(message, result.stdout)
                self.assertIn("Partial logs/FSDB are not a pass", result.stdout)

    def test_invalid_parameters_and_missing_pli(self):
        for env, message in (
            ({"AES_LOW_AREA": "2"}, "AES_LOW_AREA must be 0 or 1"),
            ({"RUN_FULL": "yes"}, "RUN_FULL must be 0 or 1"),
            ({"RUN_AES": "2"}, "RUN_AES must be 0 or 1"),
            ({"FSDB_MDA": "2"}, "FSDB_MDA must be 0 or 1"),
            ({"FSDB_FULL": "2"}, "FSDB_FULL must be 0 or 1"),
            ({"FSDB_FULL": "1", "RUN_FULL": "0"}, "FSDB_FULL=1 requires RUN_FULL=1"),
            ({"AES_BLOCKS": "1"}, "AES_BLOCKS must be 2..515"),
            ({"VERDI_HOME": None}, "Verdi PLI not found"),
            ({"VCS": str(self.home / "no-vcs")}, "VCS not found"),
        ):
            with self.subTest(env=env):
                result = self.run_script(updates=env, ok=False)
                self.assertIn(message, result.stdout)
                self.assertFalse((self.tb / "runs").exists())

    def test_lowercase_and_explicit_pli(self):
        lower = self.home / "novas/share/PLI/VCS/linux64"
        lower.mkdir(parents=True)
        for name in ("novas.tab", "pli.a"):
            (lower / name).write_text("mock\n")
        result = self.run_script(updates={"VERDI_HOME": None, "NOVAS_HOME": str(lower.parents[3]),
                                          "RUN_FULL": "0"})
        args = (self.run_dir(result) / "tb/compile_args.txt").read_text().splitlines()
        self.assertEqual(args[args.index("-P") + 1:args.index("-P") + 3],
                         [str(lower / "novas.tab"), str(lower / "pli.a")])
        result = self.run_script(updates={"VERDI_HOME": None, "VERDI_TAB": str(lower / "novas.tab"),
                                          "VERDI_PLI": str(lower / "pli.a"), "RUN_FULL": "0"})
        args = (self.run_dir(result) / "tb/compile_args.txt").read_text().splitlines()
        self.assertEqual(args[args.index("-P") + 1:args.index("-P") + 3],
                         [str(lower / "novas.tab"), str(lower / "pli.a")])


if __name__ == "__main__":
    unittest.main(verbosity=2)
