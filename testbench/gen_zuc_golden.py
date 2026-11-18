#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
ZUC Golden Keystream Generator

Generate:
    tb/golden/zuc_stream.hex
        2048 x 32-bit words

    tb/golden/zuc_stream128.hex
        512 x 128-bit blocks

Reference:
    sec_core/zuc/sec_zuc_core.py

Algorithm:
    1. Load Key / IV
    2. Run 32 initialization rounds
    3. Discard first working-mode word
    4. Generate N keystream words
"""

from pathlib import Path

from sec_core.zuc import sec_zuc_core as zuc
import os
import sys


WORD_NUM = 2048


KEY0 = [
    0x4881FF48,
    0x952C4910,
    0x82C5B300,
    0xABD6459F,
]

IV0 = [
    0xF8000000,
    0x36AF6144,
    0xF8000000,
    0x36AF6144,
]


KEY1 = [
    0x00010203,
    0x04050607,
    0x08090A0B,
    0x0C0D0E0F,
]

IV1 = [
    0x00000000,
    0x11111111,
    0x22222222,
    0x33333333,
]

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

OUTPUT_STREAM32 = os.path.join(output_dir, "zuc_stream.hex")
OUTPUT_STREAM128 = os.path.join(output_dir, "zuc_stream128.hex")

OUTPUT_STREAM32_KEY1 = os.path.join(output_dir, "zuc_stream_key1.hex")


def generate_zuc_stream(key, iv, word_num):
    """
    Generate ZUC 32-bit keystream words.

    Python model:
        init_parameters(key, iv, s, r)
        32 x zuc_core(init=1)
        1 x zuc_core(init=0), discard
        N x zuc_core(init=0)
    """

    if len(key) != 4:
        raise ValueError("Key must contain four 32-bit words")

    if len(iv) != 4:
        raise ValueError("IV must contain four 32-bit words")

    if word_num < 0:
        raise ValueError("word_num must be non-negative")

    s = [0] * 16
    r = [0] * 2

    zuc.init_parameters(
        key,
        iv,
        s,
        r,
    )

    w = 0

    # 32 initialization rounds
    for _ in range(32):

        z, w, s, r = zuc.zuc_core(
            init=1,
            w=w,
            s=s,
            r=r,
        )

    # Discard one working-mode word
    z, w, s, r = zuc.zuc_core(
        init=0,
        w=w,
        s=s,
        r=r,
    )

    # Generate actual keystream
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


def write_stream32(filename, words):
    """
    Write one 32-bit word per line.

    Example:
        12345678
        AABBCCDD
        00000001
    """

    with open(filename, "w", encoding="utf-8") as f:

        for word in words:
            f.write(f"{word:08X}\n")


def write_stream128(filename, words):
    """
    Pack every four 32-bit words into one
    128-bit keystream block.

    Block = {word0, word1, word2, word3}
    """

    if len(words) % 4 != 0:
        raise ValueError(
            "Number of words must be multiple of four"
        )

    with open(filename,"w", encoding="utf-8") as f:

        for i in range(0, len(words), 4):

            block = (
                (words[i + 0] << 96)
                | (words[i + 1] << 64)
                | (words[i + 2] << 32)
                | words[i + 3]
            )

            f.write(f"{block:032X}\n")


def print_stream_preview(name, words, count=8):

    print("")
    print(f"{name} preview:")

    for i, word in enumerate(words[:count]):
        print(f"  Z[{i:3d}] = 0x{word:08X}")


def main():

    #output_dir.mkdir(
    #    parents=True,
    #    exist_ok=True,
    #)

    print("========================================")
    print("ZUC Golden Keystream Generator")
    print("========================================")

    print(f"WORD_NUM = {WORD_NUM}")

    # KEY0 / IV0
    words0 = generate_zuc_stream(
        KEY0,
        IV0,
        WORD_NUM,
    )

    write_stream32(
        OUTPUT_STREAM32,
        words0,
    )

    write_stream128(
        OUTPUT_STREAM128,
        words0,
    )

    print_stream_preview(
        "KEY0 / IV0",
        words0,
    )

    # KEY1 / IV1
    words1 = generate_zuc_stream(
        KEY1,
        IV1,
        WORD_NUM,
    )

    write_stream32(
        OUTPUT_STREAM32_KEY1,
        words1,
    )

    print_stream_preview(
        "KEY1 / IV1",
        words1,
    )

    print("")
    print("Generated files:")
    print(f"  {OUTPUT_STREAM32}")
    print(f"  {OUTPUT_STREAM128}")
    print(f"  {OUTPUT_STREAM32_KEY1}")

    print("")
    print("Golden generation completed.")


if __name__ == "__main__":
    main()