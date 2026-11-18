#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from pathlib import Path
from math import ceil

from sec_core.zuc import sec_zuc_core as zuc
import os
import sys

PROJECT_ROOT = os.path.abspath(                           
    os.path.join(os.path.dirname(__file__), "..")         
)                                                         
sys.path.insert(0, PROJECT_ROOT)                          
                                                          
                                                          
output_dir = os.path.join(                                
    PROJECT_ROOT,                                         
    "rtl_gpt",                                            
    "tb",                                                 
    "golden"                                              
)                                                         

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

DIR0 = 0
DIR1 = 1


def build_int_iv(count, bearer, direction):
    fresh = (bearer & 0x1F) << 27

    return [
        fresh ^ (direction & 1),
        count ^ (direction & 1),
        fresh,
        count,
    ]


def generate_keystream(key, iv, word_num):

    s = [0] * 16
    r = [0] * 2

    zuc.init_parameters(key, iv, s, r)

    w = 0

    for _ in range(32):
        z, w, s, r = zuc.zuc_core(
            init=1,
            w=w,
            s=s,
            r=r,
        )

    z, w, s, r = zuc.zuc_core(
        init=0,
        w=w,
        s=s,
        r=r,
    )

    stream = []

    for _ in range(word_num):
        z, w, s, r = zuc.zuc_core(
            init=0,
            w=w,
            s=s,
            r=r,
        )

        stream.append(z & 0xFFFFFFFF)

    return stream


def get_word(stream, bit_index):

    word_index = bit_index // 32
    shift = bit_index % 32

    if shift == 0:
        return stream[word_index]

    return (
        ((stream[word_index] << shift) & 0xFFFFFFFF)
        | (stream[word_index + 1] >> (32 - shift))
    ) & 0xFFFFFFFF


def generate_mac(key, count, bearer, direction, msg):

    bit_len = len(msg) * 8
    word_num = ceil(bit_len / 32) + 2

    iv = build_int_iv(
        count,
        bearer,
        direction,
    )

    stream = generate_keystream(
        key,
        iv,
        word_num,
    )

    mac = 0

    for bit_index in range(bit_len):

        byte_index = bit_index // 8
        bit_offset = 7 - (bit_index % 8)

        if (msg[byte_index] >> bit_offset) & 1:
            mac ^= get_word(
                stream,
                bit_index,
            )

    mac ^= get_word(
        stream,
        bit_len,
    )

    mac ^= stream[ceil(bit_len / 32) + 1]

    return mac & 0xFFFFFFFF


def make_msg(length):
    return bytes(
        (i & 0xFF)
        for i in range(length)
    )


TEST_CASES = [
    (0,    KEY0, COUNT0, BEARER0, DIR0),
    (1,    KEY0, COUNT0, BEARER0, DIR0),
    (2,    KEY0, COUNT0, BEARER0, DIR0),
    (3,    KEY0, COUNT0, BEARER0, DIR0),
    (4,    KEY0, COUNT0, BEARER0, DIR0),
    (5,    KEY0, COUNT0, BEARER0, DIR0),
    (7,    KEY0, COUNT0, BEARER0, DIR0),
    (8,    KEY0, COUNT0, BEARER0, DIR0),
    (9,    KEY0, COUNT0, BEARER0, DIR0),
    (13,   KEY0, COUNT0, BEARER0, DIR0),
    (16,   KEY0, COUNT0, BEARER0, DIR0),
    (17,   KEY0, COUNT0, BEARER0, DIR0),

    (32,   KEY0, COUNT0, BEARER0, DIR0),
    (128,  KEY0, COUNT0, BEARER0, DIR0),
    (4096, KEY0, COUNT0, BEARER0, DIR0),

    (4096, KEY0, COUNT0, BEARER0, DIR0),
    (128,  KEY0, COUNT0, BEARER0, DIR0),

    (128, KEY0, COUNT1, BEARER0, DIR0),
    (128, KEY0, COUNT0, BEARER1, DIR0),
    (128, KEY0, COUNT0, BEARER0, DIR1),

    (128, KEY1, COUNT0, BEARER0, DIR0),

    (64, KEY0, COUNT0, BEARER0, DIR0),
    (64, KEY1, COUNT0, BEARER0, DIR0),
    (64, KEY0, COUNT0, BEARER0, DIR0),
]


def main():

    output = Path(
        output_dir,
        "zuc_mac_golden.hex"
    )

    output.parent.mkdir(
        parents=True,
        exist_ok=True
    )

    with output.open(
        "w",
        encoding="utf-8"
    ) as f:

        for index, (
            length,
            key,
            count,
            bearer,
            direction
        ) in enumerate(TEST_CASES):

            msg = make_msg(length)

            mac = generate_mac(
                key,
                count,
                bearer,
                direction,
                msg,
            )

            f.write(
                f"{mac:08X}\n"
            )

            print(
                f"CASE={index:02d} "
                f"LEN={length:4d} "
                f"MAC={mac:08X}"
            )

    print("")
    print(
        f"Golden written: {output}"
    )


if __name__ == "__main__":
    main()