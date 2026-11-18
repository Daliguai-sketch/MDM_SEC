#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
SEC INT TOP Golden Generator

Uses original MDM_SEC Python MAC implementations.

Output:
    tb/golden/sec_int/case_XX.hex

Each file:
    One 32-bit MAC hexadecimal value.
"""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "testbench"))

import gen_aes_cmac_golden as aes_ref
import gen_snow3g_mac_golden as snow_ref
import gen_zuc_mac_golden as zuc_ref


OUT_DIR = ROOT / "rtl_gpt" / "tb" / "golden" / "sec_int"
OUT_DIR.mkdir(parents=True, exist_ok=True)


ALG_AES = 0
ALG_SNOW = 1
ALG_ZUC = 2
ALG_NULL = 3


KEY0 = [
    0xF1722635,
    0x58DA3019,
    0x44A74CF3,
    0x83FD23A2,
]

KEY1 = [
    0x00010203,
    0x04050607,
    0x08090A0B,
    0x0C0D0E0F,
]

COUNT0 = 0x36AF6144
COUNT1 = 0x12345678

BEARER0 = 31
BEARER1 = 7

DIRECTION0 = 0
DIRECTION1 = 1


def make_message(length):
    return bytes(i & 0xFF for i in range(length))


def aes_mac(key, count, bearer, direction, msg):

    # Original AES Golden uses module-level BEARER/DIRECTION.
    aes_ref.BEARER = bearer
    aes_ref.DIRECTION = direction

    return aes_ref.generate_mac(
        key,
        count,
        len(msg)
    ) & 0xFFFFFFFF


def snow_mac(key, count, bearer, direction, msg):
    return snow_ref.generate_mac(
        key,
        count,
        bearer,
        direction,
        msg
    ) & 0xFFFFFFFF


def zuc_mac(key, count, bearer, direction, msg):
    return zuc_ref.generate_mac(
        key,
        count,
        bearer,
        direction,
        msg
    ) & 0xFFFFFFFF


def generate_case(
    case_id,
    algorithm,
    length,
    key,
    count,
    bearer,
    direction
):

    msg = make_message(length)

    if algorithm == ALG_AES:
        mac = aes_mac(
            key, count, bearer, direction, msg
        )

    elif algorithm == ALG_SNOW:
        mac = snow_mac(
            key, count, bearer, direction, msg
        )

    elif algorithm == ALG_ZUC:
        mac = zuc_mac(
            key, count, bearer, direction, msg
        )

    elif algorithm == ALG_NULL:
        mac = 0

    else:
        raise ValueError("Invalid algorithm")

    filename = OUT_DIR / f"case_{case_id:02d}.hex"

    with open(filename, "w", encoding="utf-8") as f:
        f.write(f"{mac:08X}\n")

    print(
        f"CASE {case_id:02d} "
        f"ALG={algorithm} "
        f"BYTES={length} "
        f"MAC={mac:08X}"
    )


# ==========================================================
# Test Cases
# ==========================================================

CASES = [
    (0,  ALG_AES,  128, KEY0, COUNT0, BEARER0, DIRECTION0),
    (1,  ALG_SNOW, 128, KEY0, COUNT0, BEARER0, DIRECTION0),
    (2,  ALG_ZUC,  128, KEY0, COUNT0, BEARER0, DIRECTION0),
    (3,  ALG_NULL, 128, KEY0, COUNT0, BEARER0, DIRECTION0),

    (4,  ALG_AES,  521, KEY0, COUNT0, BEARER0, DIRECTION0),
    (5,  ALG_SNOW, 513, KEY0, COUNT0, BEARER0, DIRECTION0),
    (6,  ALG_ZUC,  515, KEY0, COUNT0, BEARER0, DIRECTION0),

    (7,  ALG_AES,  128, KEY0, COUNT0, BEARER0, DIRECTION0),
    (8,  ALG_SNOW, 128, KEY0, COUNT0, BEARER0, DIRECTION0),
    (9,  ALG_ZUC,  128, KEY0, COUNT0, BEARER0, DIRECTION0),
    (10, ALG_NULL, 128, KEY0, COUNT0, BEARER0, DIRECTION0),

    (11, ALG_AES,  256, KEY1, COUNT1, BEARER1, DIRECTION1),
    (12, ALG_AES,  256, KEY0, COUNT0, BEARER0, DIRECTION0),

    (13, ALG_AES,  0, KEY0, COUNT0, BEARER0, DIRECTION0),
    (14, ALG_SNOW, 0, KEY0, COUNT0, BEARER0, DIRECTION0),
    (15, ALG_ZUC,  0, KEY0, COUNT0, BEARER0, DIRECTION0),
    (16, ALG_NULL, 0, KEY0, COUNT0, BEARER0, DIRECTION0),

    (17, ALG_AES,  4096, KEY0, COUNT0, BEARER0, DIRECTION0),
    (18, ALG_SNOW, 4096, KEY0, COUNT0, BEARER0, DIRECTION0),
    (19, ALG_ZUC,  4096, KEY0, COUNT0, BEARER0, DIRECTION0),

    (20, ALG_ZUC,  1024, KEY0, COUNT0, BEARER0, DIRECTION0),
]


def main():

    print("SEC INT GOLDEN GENERATOR")
    print("Using original MDM_SEC Python models")

    for case in CASES:
        generate_case(*case)

    print("Golden generation completed.")
    print("Output:", OUT_DIR)


if __name__ == "__main__":
    main()