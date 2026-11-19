#!/usr/bin/env python3
"""Exercise Makefile plumbing with fake tools; never claims to generate real FSDB."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

# These fakes create identifiable text files only in a TemporaryDirectory. They
# do not implement VCS, the Verdi PLI, FSDB or HDL simulation.
FAKE_VCS = r'''#!/usr/bin/env python3
import json, os, pathlib, sys
args = sys.argv[1:]
for flag in ['-full64', '-sverilog', '-debug_access+all', '-kdb', '-lca', '+memcbk', '+define+MDM_SEC_FSDB']:
    if flag not in args:
        sys.exit('missing VCS flag ' + flag)
assert '-P' in args
pos = args.index('-P')
assert pathlib.Path(args[pos+1]).is_file() and pathlib.Path(args[pos+2]).is_file()
top = args[args.index('-top')+1]
assert top in ('tb_mdm_sec', 'tb_aes_random')
for arg in args:
    if arg.endswith(('.v', '.sv', '.tab', '.a')):
        assert pathlib.Path(arg).is_file(), arg
with open('compile_args.json', 'w') as f:
    json.dump(args, f)
with open('mock_metadata.json', 'w') as f:
    json.dump({'top': top, 'args': args}, f)
pathlib.Path('simv.daidir').mkdir(exist_ok=True)
pathlib.Path('vcs_compile.log').write_text('Mock compiler only; not VCS.\n')
pathlib.Path('simv').write_text(os.environ['MOCK_SIMV_SCRIPT'])
os.chmod('simv', 0o755)
'''

FAKE_SIMV = r'''#!/usr/bin/env python3
import json, os, pathlib, sys
args = sys.argv[1:]
meta = json.loads(pathlib.Path('mock_metadata.json').read_text())
pathlib.Path('run_args.json').write_text(json.dumps(args))
assert '+CASE_LOG' in args and '+fsdb+autoflush' in args
assert '-l' in args
log = pathlib.Path(args[args.index('-l')+1])
vector = next(x.split('=',1)[1] for x in args if x.startswith('+VECTORS='))
fsdb = pathlib.Path(next(x.split('=',1)[1] for x in args if x.startswith('+FSDB=')))
assert pathlib.Path(vector).is_absolute() and pathlib.Path(vector).is_file()
assert fsdb.is_absolute()
mode = os.environ.get('MOCK_SIM_RESULT', 'pass')
if mode == 'exit':
    sys.exit(19)
if mode != 'missing':
    fsdb.write_text('MOCK OUTPUT: NOT A REAL FSDB\n')
if meta['top'] == 'tb_mdm_sec':
    assert '+DIRECTED_COVERAGE' in args
    size = next(x.split('=',1)[1] for x in meta['args'] if x.startswith('-pvalue+tb_mdm_sec.TEST_MAX_BYTES='))
    variant = next(x.split('=',1)[1] for x in meta['args'] if x.startswith('-pvalue+tb_mdm_sec.TEST_AES_LOW_AREA='))
    if mode == 'wrong_config':
        variant = '1' if variant == '0' else '0'
    config = f'DIRECTED configuration MAX_BYTES={size} AES_LOW_AREA={variant}\n'
    result = config + f'PASS directed waveform cases: mock\nPASS 20 packet vectors (MAX_BYTES={size})\n'
    if mode == 'bad_log':
        result = config + 'mock simulation failed\n'
else:
    count = next(x.split('=',1)[1] for x in args if x.startswith('+LIMIT='))
    variant = next(x.split('=',1)[1] for x in meta['args'] if x.startswith('-pvalue+tb_aes_random.TEST_AES_LOW_AREA='))
    cycles = 50 if variant == '1' else 5
    if mode == 'wrong_config':
        cycles = 50 if cycles == 5 else 5
    result = f'PASS {count} AES blocks, {cycles}-cycle latency/II, mock\n'
    if mode == 'bad_log':
        result = 'mock simulation failed\n'
log.write_text(result)
'''

FAKE_VERDI = r'''#!/usr/bin/env python3
import json, pathlib, sys
args = sys.argv[1:]
assert '-simflow' in args and '-dbdir' in args and '-ssf' in args
assert pathlib.Path(args[args.index('-dbdir')+1]).is_dir()
assert pathlib.Path(args[args.index('-ssf')+1]).is_file()
pathlib.Path('verdi_args.json').write_text(json.dumps(args))
'''


class VcsFsdbFlowTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="mdm-fsdb-test-")
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        self.build = self.home / "build"
        self.wave = self.home / "waves"
        self.vcs_home = self.home / "vcs"
        self.verdi_home = self.home / "verdi"
        self.vcs = self.vcs_home / "bin/vcs"
        self.verdi = self.verdi_home / "bin/verdi"
        self.pli = self.verdi_home / "share/PLI/VCS/LINUX64"
        for directory in (self.vcs.parent, self.verdi.parent, self.pli):
            directory.mkdir(parents=True, exist_ok=True)
        for path, content in ((self.vcs, FAKE_VCS), (self.verdi, FAKE_VERDI)):
            path.write_text(content)
            path.chmod(0o755)
        (self.pli / "novas.tab").write_text("mock PLI table\n")
        (self.pli / "pli.a").write_text("mock library\n")
        self.env = os.environ.copy()
        for key in ("VCS", "VERDI", "VCS_FLAGS", "VCS_EXTRA_FLAGS", "VCS_SIM_FLAGS",
                    "VERDI_PLI_DIR", "VERDI_TAB", "VERDI_PLI", "NOVAS_HOME", "BUILD_DIR",
                    "WAVE_DIR", "WAVE_AES_LOW_AREA", "WAVE_AES_BLOCKS", "WAVE_MAX_BYTES",
                    "FSDB_DIR", "FSDB_MDA", "MOCK_SIM_RESULT", "MAKEFLAGS", "MFLAGS",
                    "MAKELEVEL", "MAKEOVERRIDES"):
            self.env.pop(key, None)
        self.env.update(VCS_HOME=str(self.vcs_home), VERDI_HOME=str(self.verdi_home),
                        MOCK_SIMV_SCRIPT=FAKE_SIMV)
        self.options = [f"BUILD_DIR={self.build}", f"FSDB_DIR={self.wave}", f"PYTHON={sys.executable}"]

    def make(self, *args, ok=True, env=None):
        result = subprocess.run(["make", "--no-print-directory", *args, *self.options],
                                cwd=ROOT, env=env or self.env, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        if ok and result.returncode != 0:
            self.fail(f"make {' '.join(args)} unexpectedly failed:\n{result.stdout}")
        if not ok and result.returncode == 0:
            self.fail(f"make {' '.join(args)} unexpectedly succeeded:\n{result.stdout}")
        return result.stdout

    def test_both_variants_flags_and_verdi(self):
        options = ("WAVE_AES_LOW_AREA=0", "WAVE_AES_BLOCKS=2", "FSDB_MDA=1")
        out = self.make("-j", "2", "fsdb", *options)
        self.assertIn("PASS packet self-check and nonempty FSDB", out)
        self.assertIn("PASS AES self-check and nonempty FSDB", out)
        packet = self.build / "vcs_packet_512_0"
        aes = self.build / "vcs_aes_0"
        self.assertEqual((self.wave / "mdm_sec_fast.fsdb").read_text(), "MOCK OUTPUT: NOT A REAL FSDB\n")
        self.assertEqual((self.wave / "aes128_fast.fsdb").read_text(), "MOCK OUTPUT: NOT A REAL FSDB\n")
        pargs = json.loads((packet / "compile_args.json").read_text())
        aargs = json.loads((aes / "compile_args.json").read_text())
        self.assertIn("-pvalue+tb_mdm_sec.TEST_MAX_BYTES=512", pargs)
        self.assertIn("-pvalue+tb_mdm_sec.TEST_AES_LOW_AREA=0", pargs)
        self.assertIn("-pvalue+tb_aes_random.TEST_AES_LOW_AREA=0", aargs)
        self.assertEqual(pargs[pargs.index("-P")+1:pargs.index("-P")+3],
                         [str(self.pli / "novas.tab"), str(self.pli / "pli.a")])
        self.assertIn("+FSDB_MDA", json.loads((packet / "run_args.json").read_text()))
        self.assertNotIn("+FSDB_MDA", json.loads((aes / "run_args.json").read_text()))
        self.assertEqual(len((self.build / "wave_vectors.cases.txt").read_text().splitlines()), 20)
        self.make("verdi-packet", *options)
        self.make("verdi-aes", *options)
        for directory, filename in ((packet, "mdm_sec_fast.fsdb"), (aes, "aes128_fast.fsdb")):
            args = json.loads((directory / "verdi_args.json").read_text())
            self.assertEqual(args[args.index("-ssf")+1], str(self.wave / filename))

    def test_balanced_variant_flags_and_wave_names(self):
        options = ("WAVE_AES_LOW_AREA=2", "WAVE_AES_BLOCKS=2")
        self.make("-j", "2", "fsdb", *options)
        packet = self.build / "vcs_packet_512_2"
        aes = self.build / "vcs_aes_2"
        self.assertIn("-pvalue+tb_mdm_sec.TEST_AES_LOW_AREA=2",
                      json.loads((packet / "compile_args.json").read_text()))
        self.assertIn("-pvalue+tb_aes_random.TEST_AES_LOW_AREA=2",
                      json.loads((aes / "compile_args.json").read_text()))
        self.assertIn("PASS 2 AES blocks, 5-cycle latency/II", (aes / "sim.log").read_text())
        self.assertTrue((self.wave / "mdm_sec_balanced.fsdb").is_file())
        self.assertTrue((self.wave / "aes128_balanced.fsdb").is_file())

    def test_lowercase_pli_and_default_variant(self):
        lower_home = self.home / "novas"
        lower = lower_home / "share/PLI/VCS/linux64"
        lower.mkdir(parents=True)
        for name in ("novas.tab", "pli.a"):
            (lower / name).write_text("mock\n")
        env = self.env.copy()
        env.pop("VERDI_HOME")
        env["NOVAS_HOME"] = str(lower_home)
        self.make("fsdb-packet", "WAVE_MAX_BYTES=2048", env=env)
        args = json.loads((self.build / "vcs_packet_2048_1/compile_args.json").read_text())
        self.assertEqual(args[args.index("-P")+1:args.index("-P")+3],
                         [str(lower / "novas.tab"), str(lower / "pli.a")])
        self.assertIn("-pvalue+tb_mdm_sec.TEST_MAX_BYTES=2048", args)
        self.assertNotIn("+FSDB_MDA", json.loads((self.build / "vcs_packet_2048_1/run_args.json").read_text()))
        self.assertTrue((self.wave / "mdm_sec_low_area.fsdb").is_file())

    def test_explicit_pli_paths(self):
        env = self.env.copy()
        env.pop("VERDI_HOME")
        self.make("fsdb-aes", f"VCS={self.vcs}", f"VERDI_TAB={self.pli / 'novas.tab'}",
                  f"VERDI_PLI={self.pli / 'pli.a'}", env=env)
        args = json.loads((self.build / "vcs_aes_1/compile_args.json").read_text())
        self.assertEqual(args[args.index("-P")+1:args.index("-P")+3],
                         [str(self.pli / "novas.tab"), str(self.pli / "pli.a")])
        self.assertTrue((self.wave / "aes128_low_area.fsdb").is_file())

    def test_missing_tools_and_pli(self):
        out = self.make("fsdb-packet", f"VCS={self.home}/missing-vcs", ok=False)
        self.assertIn("Install/configure VCS", out)
        env = self.env.copy()
        env.pop("VERDI_HOME")
        out = self.make("fsdb-packet", ok=False, env=env)
        self.assertIn("Verdi PLI not found", out)
        out = self.make("verdi-packet", ok=False)
        self.assertIn("Run make fsdb-packet", out)

    def test_fails_closed_on_missing_fsdb_and_failed_run(self):
        self.make("fsdb-packet")
        output = self.wave / "mdm_sec_low_area.fsdb"
        self.assertTrue(output.is_file())
        env = self.env.copy()
        env["MOCK_SIM_RESULT"] = "missing"
        out = self.make("fsdb-packet", ok=False, env=env)
        self.assertIn("Packet FSDB missing or empty", out)
        self.assertFalse(output.exists(), "stale file must be removed before simulation")
        env["MOCK_SIM_RESULT"] = "bad_log"
        out = self.make("fsdb-packet", ok=False, env=env)
        self.assertIn("Packet self-check/coverage did not pass", out)
        env["MOCK_SIM_RESULT"] = "exit"
        self.make("fsdb-packet", ok=False, env=env)
        self.assertFalse(output.exists(), "file from the failed run must not be left stale")

    def test_aes_missing_file_and_failed_scoreboard(self):
        options = ("WAVE_AES_BLOCKS=2",)
        self.make("fsdb-aes", *options)
        output = self.wave / "aes128_low_area.fsdb"
        self.assertTrue(output.is_file())
        env = self.env.copy()
        env["MOCK_SIM_RESULT"] = "missing"
        self.assertIn("AES FSDB missing or empty", self.make("fsdb-aes", *options, ok=False, env=env))
        self.assertFalse(output.exists())
        env["MOCK_SIM_RESULT"] = "bad_log"
        self.assertIn("AES self-check or AES_LOW_AREA parameter did not pass", self.make("fsdb-aes", *options, ok=False, env=env))

    def test_parameter_override_is_not_silently_ignored(self):
        self.make("fsdb", "WAVE_AES_LOW_AREA=0")
        env = self.env.copy()
        env["MOCK_SIM_RESULT"] = "wrong_config"
        self.assertIn("Packet VCS parameter mismatch",
                      self.make("fsdb-packet", "WAVE_AES_LOW_AREA=0", ok=False, env=env))
        self.assertIn("AES self-check or AES_LOW_AREA parameter did not pass",
                      self.make("fsdb-aes", "WAVE_AES_LOW_AREA=0", ok=False, env=env))

    def test_parameter_guards(self):
        self.assertIn("WAVE_AES_LOW_AREA must be 0, 1 or 2",
                      self.make("fsdb-packet", "WAVE_AES_LOW_AREA=3", ok=False))
        self.assertIn("WAVE_MAX_BYTES must be 512..65535",
                      self.make("fsdb-packet", "WAVE_MAX_BYTES=511", ok=False))
        self.assertIn("FSDB_MDA must be 0 or 1",
                      self.make("fsdb-packet", "FSDB_MDA=2", ok=False))
        self.assertIn("WAVE_AES_BLOCKS must be 2",
                      self.make("fsdb-aes", "WAVE_AES_BLOCKS=1", ok=False))


if __name__ == "__main__":
    unittest.main(verbosity=2)
