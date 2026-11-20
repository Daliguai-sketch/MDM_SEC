#!/usr/bin/env python3
"""Smoke-check waveform contents, key transitions and self-checking examples."""
import argparse
from pathlib import Path

PACKET_ROOT = "tb_mdm_sec"
AES_ROOT = "tb_aes_random"


def read_header(stream):
    scope = []
    signals = {}
    have_timescale = False
    for line in stream:
        fields = line.split()
        if not fields:
            continue
        if fields[0] == "$timescale":
            have_timescale = True
        elif fields[0] == "$scope":
            scope.append(fields[2])
        elif fields[0] == "$upscope":
            if not scope:
                raise ValueError("unbalanced VCD scope")
            scope.pop()
        elif fields[0] == "$var":
            if len(fields) < 6:
                raise ValueError("malformed VCD variable declaration")
            signals[".".join(scope + [fields[4]])] = fields[3]
        elif fields[0] == "$enddefinitions":
            if not have_timescale:
                raise ValueError("VCD has no timescale")
            return signals
    raise ValueError("VCD has no enddefinitions")


def add_aes_core_checks(signals, wrapper, required, additional):
    """Require a traced, active implementation, not just wrapper ports."""
    variants = (("g_low_area", "round"), ("g_fast", "pair"), ("g_balanced", "pair"))
    found = [(name, f"{wrapper}.{name}.u_core") for name, counter in variants
             if f"{wrapper}.{name}.u_core.{counter}" in signals]
    if len(found) != 1:
        raise ValueError(
            f"AES u_core internals missing or ambiguous below {wrapper}; "
            "check the trace depth or FSDB dump scope and matching design database"
        )
    name, core = found[0]
    required[f"{core}.state"] = {0, 1}
    required[f"{core}.busy"] = {0, 1}
    required[f"{core}.done"] = {0, 1}
    if name == "g_low_area":
        required[f"{core}.round"] = {0, 9}
        required[f"{core}.column"] = {0, 1, 2, 3}
    else:
        required[f"{core}.pair"] = {0, 4}
    additional.extend((f"{core}.round_state", f"{core}.key_reg", f"{core}.rcon"))
    return name


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("profile", choices=("packet", "aes"))
    parser.add_argument("vcd", type=Path)
    args = parser.parse_args()
    if args.profile == "packet":
        root = PACKET_ROOT
        required = {
            f"{root}.clk": {0, 1}, f"{root}.rst_n": {0, 1},
            f"{root}.wave_phase": set(range(7)), f"{root}.wave_case_id": set(range(20)),
            f"{root}.cmd_mode": set(range(6)), f"{root}.rsp_valid": {0, 1},
            f"{root}.cipher_valid": {0, 1}, f"{root}.rsp_rx_mac_valid": {0, 1},
            f"{root}.rsp_mac_match": {0, 1}, f"{root}.dut.enc_start": {0, 1},
            f"{root}.dut.int_start": {0, 1}, f"{root}.dut.enc_mem_ready": {0, 1},
            f"{root}.dut.int_dep_ready": {0, 1}, f"{root}.dut.result_wr_en": {0, 1},
        }
        additional = [f"{root}.dut.u_input_buffer.wr_addr", f"{root}.dut.u_input_buffer.rd0_addr",
                      f"{root}.dut.u_input_buffer.rd1_addr"]
    else:
        root = AES_ROOT
        required = {f"{root}.{name}": {0, 1}
                    for name in ("clk", "rst_n", "start", "ready", "busy", "done", "scoreboard_active")}
        required[f"{root}.block_out"] = {int("69c4e0d86a7b0430d8cdb78070b4c55a", 16)}
        additional = []

    with args.vcd.open() as stream:
        signals = read_header(stream)
        if args.profile == "aes":
            add_aes_core_checks(signals, f"{root}.dut", required, additional)
        else:
            variants = [add_aes_core_checks(signals, f"{root}.dut.{lane}.u_aes", required, additional)
                        for lane in ("u_cipher", "u_integrity")]
            if variants[0] != variants[1]:
                raise ValueError(f"AES variants differ between packet lanes: {variants}")
        missing = [name for name in (*required, *additional) if name not in signals]
        if missing:
            raise ValueError("VCD is missing required signals: " + ", ".join(missing))
        tracked_ids = {signals[name] for name in (*required, *additional)}
        current = {}
        seen = {code: set() for code in tracked_ids}
        observations = set()
        times = 0
        last_time = -1

        def sample():
            if args.profile != "packet":
                return
            case = current.get(signals[f"{root}.wave_case_id"])
            rsp = current.get(signals[f"{root}.rsp_valid"])
            rx_valid = current.get(signals[f"{root}.rsp_rx_mac_valid"])
            match = current.get(signals[f"{root}.rsp_mac_match"])
            if rsp == 1 and rx_valid == 1 and case in (11, 12, 13, 18, 19):
                observations.add((case, match))

        for line in stream:
            line = line.strip()
            if not line:
                continue
            if line.startswith("#"):
                sample()
                when = int(line[1:])
                if when < last_time:
                    raise ValueError("VCD time moved backwards")
                last_time = when
                times += 1
                continue
            if line[0] in "01xXzZ":
                value, code = line[0], line[1:]
            elif line[0] in "bB":
                fields = line[1:].split()
                if len(fields) != 2:
                    continue
                value, code = fields
            else:
                continue
            if code in tracked_ids:
                if all(c in "01" for c in value):
                    number = int(value, 2)
                    current[code] = number
                    seen[code].add(number)
                else:
                    current.pop(code, None)
        sample()

    if times < 2 or last_time <= 0:
        raise ValueError("VCD has no advancing simulation time")
    for name, expected in required.items():
        if not expected.issubset(seen[signals[name]]):
            raise ValueError(f"{name} is missing expected values {expected - seen[signals[name]]}")
    for name in additional:
        if len(seen[signals[name]]) < 2:
            raise ValueError(f"{name} never changes")
    if args.profile == "packet":
        expected_observations = {(11, 1), (12, 0), (13, 1), (18, 1), (19, 0)}
        if not expected_observations.issubset(observations):
            raise ValueError(f"missing mode-5 waveform responses: {expected_observations - observations}")
    print(f"PASS {args.profile} VCD: {len(signals)} signals, {times} timestamps, {args.vcd}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as exc:
        raise SystemExit(f"ERROR: {exc}") from exc
