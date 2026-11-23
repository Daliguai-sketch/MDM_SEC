#!/usr/bin/env python3
"""Regression checks for packet VCD AES hierarchy and activity validation."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
CHECKER = ROOT / "tests/check_vcd.py"
PACKET = "tb_mdm_sec"


def packet_vcd(cipher, integrity, *, stuck_lane=None):
    """Build a small syntactically valid waveform with 20 directed cases."""
    signals = {}

    def add(path, width=1):
        signals[path] = (width, f"v{len(signals)}")

    for name in ("clk", "rst_n", "rsp_valid", "cipher_valid", "rsp_rx_mac_valid", "rsp_mac_match"):
        add(f"{PACKET}.{name}")
    for name in ("wave_phase", "wave_case_id", "cmd_mode"):
        add(f"{PACKET}.{name}", 32)
    for name in ("enc_start", "int_start", "enc_mem_ready", "int_dep_ready", "result_wr_en"):
        add(f"{PACKET}.dut.{name}")
    for name in ("wr_addr", "rd0_addr", "rd1_addr"):
        add(f"{PACKET}.dut.u_input_buffer.{name}", 16)

    core_paths = {}
    for lane, variant in (("u_cipher", cipher), ("u_integrity", integrity)):
        if variant is None:
            continue
        core = f"{PACKET}.dut.{lane}.u_aes.{variant}.u_core"
        core_paths[lane] = core
        for name in ("state", "busy", "done"):
            add(f"{core}.{name}", 2 if name == "state" else 1)
        for name in ("round_state", "key_reg", "rcon"):
            add(f"{core}.{name}", 128 if name != "rcon" else 8)
        if variant == "g_low_area":
            add(f"{core}.round", 4)
            add(f"{core}.column", 2)
        else:
            add(f"{core}.pair", 3)

    # Construct proper nested scopes; VCD identifier aliases are unnecessary.
    tree = {}
    for path, (width, code) in signals.items():
        parts = path.split(".")
        node = tree
        for part in parts[:-1]:
            node = node.setdefault(part, {})
        node.setdefault(None, []).append((parts[-1], width, code))

    lines = ["$timescale 1ps $end"]

    def declare(node):
        for name, width, code in node.get(None, []):
            lines.append(f"$var wire {width} {code} {name} $end")
        for scope, child in node.items():
            if scope is None:
                continue
            lines.append(f"$scope module {scope} $end")
            declare(child)
            lines.append("$upscope $end")

    declare(tree)
    lines.extend(("$enddefinitions $end", "#0"))
    lines.extend(f"b0 {code}" for _, code in signals.values())
    for case in range(20):
        values = {path: case % 2 for path in signals}
        values[f"{PACKET}.wave_case_id"] = case
        values[f"{PACKET}.wave_phase"] = case % 7
        values[f"{PACKET}.cmd_mode"] = case % 6
        values[f"{PACKET}.rsp_valid"] = 1
        values[f"{PACKET}.rsp_rx_mac_valid"] = 1
        values[f"{PACKET}.rsp_mac_match"] = {11: 1, 12: 0, 13: 1, 18: 1, 19: 0}.get(case, case % 2)
        for name in ("wr_addr", "rd0_addr", "rd1_addr"):
            values[f"{PACKET}.dut.u_input_buffer.{name}"] = case + 1
        for lane, core in core_paths.items():
            values[f"{core}.state"] = 0 if lane == stuck_lane else case % 2
            for name in ("round_state", "key_reg", "rcon"):
                values[f"{core}.{name}"] = case + 1
            if f"{core}.round" in signals:
                values[f"{core}.round"] = case % 10
                values[f"{core}.column"] = case % 4
            else:
                values[f"{core}.pair"] = case % 5
        lines.append(f"#{case + 1}")
        for path, (_, code) in signals.items():
            lines.append(f"b{values[path]:b} {code}")
    return "\n".join(lines) + "\n"


class PacketVcdCheckTests(unittest.TestCase):
    def run_check(self, contents):
        with tempfile.TemporaryDirectory(prefix="mdm-vcd-test-") as work:
            path = Path(work) / "packet.vcd"
            path.write_text(contents, encoding="ascii")
            return subprocess.run([sys.executable, str(CHECKER), "packet", str(path)],
                                  text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)

    def test_each_aes_variant_in_both_lanes(self):
        for variant in ("g_low_area", "g_fast", "g_balanced"):
            with self.subTest(variant=variant):
                result = self.run_check(packet_vcd(variant, variant))
                self.assertEqual(result.returncode, 0, result.stdout)
                self.assertIn("PASS packet VCD", result.stdout)

    def test_balanced_integrity_timing_trace(self):
        result = self.run_check(packet_vcd("g_balanced", "g_balanced_timing"))
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("PASS packet VCD", result.stdout)

    def test_old_shallow_trace_is_rejected(self):
        result = self.run_check(packet_vcd(None, None))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("AES u_core internals missing", result.stdout)
        self.assertIn("dut.u_cipher.u_aes", result.stdout)

    def test_missing_integrity_core_is_rejected(self):
        result = self.run_check(packet_vcd("g_fast", None))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("dut.u_integrity.u_aes", result.stdout)

    def test_mismatched_lane_variants_are_rejected(self):
        result = self.run_check(packet_vcd("g_fast", "g_balanced"))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("AES variants differ", result.stdout)

    def test_core_state_must_really_change(self):
        result = self.run_check(packet_vcd("g_fast", "g_fast", stuck_lane="u_cipher"))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("u_cipher.u_aes.g_fast.u_core.state is missing expected values", result.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
