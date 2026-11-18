#!/usr/bin/env python3

from pathlib import Path

from sec_core.snow3g import sec_snow3g_core as snow
import os
import sys

PROJECT_ROOT = os.path.abspath(                  
    os.path.join(os.path.dirname(__file__), "..")
)                                                
                                                                                            
sys.path.insert(0, PROJECT_ROOT)                 

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


def mulx64(v):
    if v & (1 << 63):
        return ((v << 1) ^ 0x1B) & 0xFFFFFFFFFFFFFFFF
    return (v << 1) & 0xFFFFFFFFFFFFFFFF


def eval_mul64(p, m):
    result = 0
    temp = m

    for bit in range(64):
        if (p >> bit) & 1:
            result ^= temp

        temp = mulx64(temp)

    return result


def build_int_iv(count, bearer, direction):
    fresh = (bearer & 0x1F) << 27

    iv0 = fresh ^ ((direction & 1) << 15)
    iv1 = count ^ (direction & 1)
    iv2 = fresh
    iv3 = count

    return [
        iv0 & 0xFFFFFFFF,
        iv1 & 0xFFFFFFFF,
        iv2 & 0xFFFFFFFF,
        iv3 & 0xFFFFFFFF,
    ]


def generate_keystream(key, iv, words=5):
    s = [0] * 16
    r = [0] * 3

    snow.init_parameters(key, iv, s, r)

    w = 0

    for _ in range(32):
        z, w, s, r = snow.snow_3g_core(
            init=1,
            w=w,
            s=s,
            r=r,
        )

    z, w, s, r = snow.snow_3g_core(
        init=0,
        w=w,
        s=s,
        r=r,
    )

    result = []

    for _ in range(words):
        z, w, s, r = snow.snow_3g_core(
            init=0,
            w=w,
            s=s,
            r=r,
        )

        result.append(z & 0xFFFFFFFF)

    return result


def generate_mac(key, count, bearer, direction, msg):
    iv = build_int_iv(count, bearer, direction)

    z = generate_keystream(key, iv, 5)

    p = ((z[0] << 32) | z[1]) & 0xFFFFFFFFFFFFFFFF
    q = ((z[2] << 32) | z[3]) & 0xFFFFFFFFFFFFFFFF
    otp = z[4]

    result = 0

    for offset in range(0, len(msg), 8):
        chunk = msg[offset:offset + 8]

        block = int.from_bytes(
            chunk.ljust(8, b"\x00"),
            byteorder="big",
        )

        result = eval_mul64(
            p,
            result ^ block,
        )

    length_block = (len(msg) * 8) & 0xFFFFFFFFFFFFFFFF

    result = eval_mul64(
        q,
        result ^ length_block,
    )

    return ((result >> 32) ^ otp) & 0xFFFFFFFF


def make_msg(length):
    return bytes((i & 0xFF) for i in range(length))


TEST_CASES = [
    (0,    KEY0, COUNT0, BEARER0, DIRECTION0),
    (1,    KEY0, COUNT0, BEARER0, DIRECTION0),
    (7,    KEY0, COUNT0, BEARER0, DIRECTION0),
    (8,    KEY0, COUNT0, BEARER0, DIRECTION0),
    (9,    KEY0, COUNT0, BEARER0, DIRECTION0),
    (13,   KEY0, COUNT0, BEARER0, DIRECTION0),
    (16,   KEY0, COUNT0, BEARER0, DIRECTION0),
    (17,   KEY0, COUNT0, BEARER0, DIRECTION0),
    (32,   KEY0, COUNT0, BEARER0, DIRECTION0),
    (128,  KEY0, COUNT0, BEARER0, DIRECTION0),
    (4096, KEY0, COUNT0, BEARER0, DIRECTION0),

    # Random input gaps: same message, same MAC
    (4096, KEY0, COUNT0, BEARER0, DIRECTION0),

    # Output backpressure
    (128, KEY0, COUNT0, BEARER0, DIRECTION0),

    # Same key, different count
    (128, KEY0, COUNT1, BEARER0, DIRECTION0),

    # Different direction
    (128, KEY0, COUNT0, BEARER0, DIRECTION1),

    # Different bearer
    (128, KEY0, COUNT0, BEARER1, DIRECTION0),

    # Different key
    (128, KEY1, COUNT0, BEARER0, DIRECTION0),

    # Key0 -> Key1 -> Key0
    (64, KEY0, COUNT0, BEARER0, DIRECTION0),
    (64, KEY1, COUNT0, BEARER0, DIRECTION0),
    (64, KEY0, COUNT0, BEARER0, DIRECTION0),
]


def main():
    output_dir = os.path.join(
        PROJECT_ROOT,
        "rtl_gpt",
        "tb",
        "golden"
    )
    output_file = os.path.join(output_dir, "snow3g_mac_golden.hex")
    with open(output_file,"w", encoding="utf-8") as f:
        for idx, (length, key, count, bearer, direction) in enumerate(TEST_CASES):
            msg = make_msg(length)

            mac = generate_mac(
                key,
                count,
                bearer,
                direction,
                msg,
            )

            f.write(f"{mac:08X}\n")

            print(
                f"CASE={idx:02d} "
                f"LEN={length:4d} "
                f"MAC={mac:08X}"
            )

    print(f"\nGolden written: {output_file}")


if __name__ == "__main__":
    main()