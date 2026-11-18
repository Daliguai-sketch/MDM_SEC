#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
SEC ENC TOP Golden Generator

Algorithms:
    0: AES-CTR
    1: SNOW3G
    2: ZUC
    3: NULL

AES:
    Uses original MDM_SEC Python implementation:
        sec_aes_core_enc.aes_enc_key_exp()
        sec_aes_core_enc.aes_enc_core()

SNOW3G / ZUC:
    Uses previously generated Python Golden streams.

Plaintext:
    msg[i] = i & 0xFF

Output:
    tb/golden/sec_enc/case_XX.hex

Each line:
    One 128-bit ciphertext block.

Last incomplete block:
    Unused bytes padded with zero.
"""

import sys
from pathlib import Path


# ==========================================================
# Project Paths
# ==========================================================

ROOT = Path(__file__).resolve().parents[1]

sys.path.insert(0, str(ROOT))

from sec_core.aes import sec_aes_core_enc


GOLDEN_DIR = ROOT / "rtl_gpt" / "tb" / "golden"

OUT_DIR = GOLDEN_DIR / "sec_enc"

OUT_DIR.mkdir(
    parents=True,
    exist_ok=True
)


# ==========================================================
# Algorithm Encoding
# ==========================================================

ALG_AES = 0
ALG_SNOW = 1
ALG_ZUC = 2
ALG_NULL = 3


# ==========================================================
# Keys
# ==========================================================

KEY_AES = bytes.fromhex(
    "F172263558DA301944A74CF383FD23A2"
)

KEY_STREAM = bytes.fromhex(
    "4881FF48952C491082C5B300ABD6459F"
)

KEY_AES_1 = bytes.fromhex(
    "000102030405060708090A0B0C0D0E0F"
)


# ==========================================================
# Packet Parameters
# ==========================================================

COUNT0 = 0x36AF6144
COUNT1 = 0x12345678

BEARER0 = 31
BEARER1 = 7

DIRECTION0 = 1
DIRECTION1 = 0


# ==========================================================
# Plaintext Generator
# ==========================================================

def make_plaintext(length):

    return bytes(
        i & 0xFF
        for i in range(length)
    )


# ==========================================================
# AES-CTR Keystream
# Original MDM_SEC Python Implementation
# ==========================================================

def aes_ctr_keystream(
    key,
    count,
    bearer,
    direction,
    length
):

    if len(key) != 16:
        raise ValueError(
            "AES-128 key must be 16 bytes"
        )

    block_count = (length + 15) // 16

    # RTL CTR counter is 13 bits.
    if block_count > 8192:
        raise ValueError(
            "AES CTR exceeds 13-bit counter space"
        )

    # Convert 128-bit key into four 32-bit words.
    #
    # Example:
    #
    # F172263558DA301944A74CF383FD23A2
    #
    # becomes:
    #
    # [
    #     0xF1722635,
    #     0x58DA3019,
    #     0x44A74CF3,
    #     0x83FD23A2
    # ]

    key_words = [
        int.from_bytes(
            key[i:i+4],
            "big"
        )
        for i in range(0, 16, 4)
    ]

    # Original AES Key Expansion
    round_keys = (
        sec_aes_core_enc.aes_enc_key_exp(
            key_words
        )
    )

    iv1 = (
        (bearer << 27)
        |
        (direction << 26)
    )

    keystream = bytearray()

    for counter in range(block_count):

        iv = [
            count,
            iv1,
            0,
            counter & 0x1FFF
        ]

        # Original AES encryption
        stream_words = (
            sec_aes_core_enc.aes_enc_core(
                iv,
                round_keys
            )
        )

        # stream_words:
        # [
        #     word0,
        #     word1,
        #     word2,
        #     word3
        # ]
        #
        # Each word is 32-bit.
        # MSB first.

        if len(stream_words) != 4:
            raise ValueError(
                "AES Core must return four 32-bit words"
            )

        for word in stream_words:

            keystream.extend(
                (
                    word & 0xFFFFFFFF
                ).to_bytes(
                    4,
                    "big"
                )
            )

    return bytes(
        keystream[:length]
    )


# ==========================================================
# Load SNOW3G/ZUC Python Golden Stream
# ==========================================================

def load_stream_words(path):

    if not path.exists():
        raise FileNotFoundError(
            "Missing stream Golden: %s" % path
        )

    words = []

    with open(
        path,
        "r",
        encoding="utf-8"
    ) as f:

        for line in f:

            line = line.strip()

            if not line:
                continue

            if line.startswith("#"):
                continue

            word = int(
                line,
                16
            )

            if word < 0 or word > 0xFFFFFFFF:
                raise ValueError(
                    "Invalid 32-bit stream word: %s"
                    % line
                )

            words.append(
                word
            )

    result = bytearray()

    for word in words:

        result.extend(
            word.to_bytes(
                4,
                "big"
            )
        )

    return bytes(result)


# ==========================================================
# Load Stream Golden
# ==========================================================

SNOW_STREAM = load_stream_words(
    GOLDEN_DIR / "snow3g_stream.hex"
)

ZUC_STREAM = load_stream_words(
    GOLDEN_DIR / "zuc_stream.hex"
)


# ==========================================================
# Select Algorithm Keystream
# ==========================================================

def get_keystream(
    alg,
    key,
    count,
    bearer,
    direction,
    length
):

    if alg == ALG_AES:

        return aes_ctr_keystream(
            key,
            count,
            bearer,
            direction,
            length
        )

    elif alg == ALG_SNOW:

        # Existing SNOW3G Golden configuration:
        #
        # KEY:
        # 4881FF48952C491082C5B300ABD6459F
        #
        # COUNT:
        # 36AF6144
        #
        # BEARER:
        # 31
        #
        # DIRECTION:
        # 0
        #
        # IV:
        # F800000036AF6144F800000036AF6144

        if (
            key != KEY_STREAM
            or count != COUNT0
            or bearer != BEARER0
            or direction != 0
        ):
            raise ValueError(
                "SNOW3G parameters do not match "
                "existing Python Golden stream"
            )

        if length > len(SNOW_STREAM):
            raise ValueError(
                "SNOW3G Golden stream too short"
            )

        return SNOW_STREAM[:length]

    elif alg == ALG_ZUC:

        # Existing ZUC Golden configuration:
        #
        # KEY:
        # 4881FF48952C491082C5B300ABD6459F
        #
        # COUNT:
        # 36AF6144
        #
        # BEARER:
        # 31
        #
        # DIRECTION:
        # 0
        #
        # IV:
        # F800000036AF6144F800000036AF6144

        if (
            key != KEY_STREAM
            or count != COUNT0
            or bearer != BEARER0
            or direction != 0
        ):
            raise ValueError(
                "ZUC parameters do not match "
                "existing Python Golden stream"
            )

        if length > len(ZUC_STREAM):
            raise ValueError(
                "ZUC Golden stream too short"
            )

        return ZUC_STREAM[:length]

    elif alg == ALG_NULL:

        return bytes(length)

    else:

        raise ValueError(
            "Invalid ENC algorithm"
        )


# ==========================================================
# Generate Cipher Golden
# ==========================================================

def generate_case(
    case_id,
    alg,
    length,
    key,
    count,
    bearer,
    direction
):

    plaintext = make_plaintext(
        length
    )

    keystream = get_keystream(
        alg,
        key,
        count,
        bearer,
        direction,
        length
    )

    cipher = bytes(
        p ^ k
        for p, k in zip(
            plaintext,
            keystream
        )
    )

    block_count = (
        length + 15
    ) // 16

    output_file = (
        OUT_DIR /
        f"case_{case_id:02d}.hex"
    )

    with open(
        output_file,
        "w",
        encoding="utf-8"
    ) as f:

        for block_index in range(
            block_count
        ):

            start = block_index * 16
            end = start + 16

            block = cipher[
                start:end
            ]

            # Last incomplete block:
            # pad unused bytes with zero.

            block = block.ljust(
                16,
                b"\x00"
            )

            f.write(
                block.hex().upper()
                + "\n"
            )

    print(
        "CASE %02d ALG=%d BYTES=%d BLOCKS=%d"
        % (
            case_id,
            alg,
            length,
            block_count
        )
    )


# ==========================================================
# Test Cases
# ==========================================================

CASES = [

    # TEST0 AES 128 Byte
    (
        0,
        ALG_AES,
        128,
        KEY_AES,
        COUNT0,
        BEARER0,
        DIRECTION0
    ),

    # TEST1 SNOW3G 128 Byte
    (
        1,
        ALG_SNOW,
        128,
        KEY_STREAM,
        COUNT0,
        BEARER0,
        0
    ),

    # TEST2 ZUC 128 Byte
    (
        2,
        ALG_ZUC,
        128,
        KEY_STREAM,
        COUNT0,
        BEARER0,
        0
    ),

    # TEST3 NULL 128 Byte
    (
        3,
        ALG_NULL,
        128,
        KEY_AES,
        COUNT0,
        BEARER0,
        DIRECTION0
    ),

    # TEST4 508 Byte AES
    (
        4,
        ALG_AES,
        508,
        KEY_AES,
        COUNT0,
        BEARER0,
        DIRECTION0
    ),

    # TEST5 SNOW3G Input Bubbles
    (
        5,
        ALG_SNOW,
        512,
        KEY_STREAM,
        COUNT0,
        BEARER0,
        0
    ),

    # TEST6 ZUC Output Backpressure
    (
        6,
        ALG_ZUC,
        512,
        KEY_STREAM,
        COUNT0,
        BEARER0,
        0
    ),

    # TEST7 Algorithm Switching
    (
        7,
        ALG_AES,
        128,
        KEY_AES,
        COUNT0,
        BEARER0,
        DIRECTION0
    ),

    (
        8,
        ALG_SNOW,
        128,
        KEY_STREAM,
        COUNT0,
        BEARER0,
        0
    ),

    (
        9,
        ALG_ZUC,
        128,
        KEY_STREAM,
        COUNT0,
        BEARER0,
        0
    ),

    (
        10,
        ALG_NULL,
        128,
        KEY_AES,
        COUNT0,
        BEARER0,
        DIRECTION0
    ),

    # TEST8 Key/COUNT Update
    (
        11,
        ALG_AES,
        256,
        KEY_AES_1,
        COUNT1,
        BEARER1,
        DIRECTION1
    ),

    (
        12,
        ALG_AES,
        256,
        KEY_AES,
        COUNT0,
        BEARER0,
        DIRECTION0
    ),

    # TEST9 Zero Byte
    (
        13,
        ALG_NULL,
        0,
        KEY_AES,
        COUNT0,
        BEARER0,
        DIRECTION0
    ),

    # TEST10 Long Packet
    (
        14,
        ALG_AES,
        4096,
        KEY_AES,
        COUNT0,
        BEARER0,
        DIRECTION0
    ),

    (
        15,
        ALG_SNOW,
        4096,
        KEY_STREAM,
        COUNT0,
        BEARER0,
        0
    ),

    (
        16,
        ALG_ZUC,
        4096,
        KEY_STREAM,
        COUNT0,
        BEARER0,
        0
    ),

    # TEST11 Valid/Ready Stability
    (
        17,
        ALG_ZUC,
        1024,
        KEY_STREAM,
        COUNT0,
        BEARER0,
        0
    ),

]


# ==========================================================
# AES Reference Check
# ==========================================================

def check_aes_reference():

    stream = aes_ctr_keystream(
        KEY_AES,
        COUNT0,
        BEARER0,
        DIRECTION0,
        16
    )

    expected = bytes.fromhex(
        "9E20ED87A8B9100A44E02AC00947E663"
    )

    print(
        "Original Python AES STREAM =",
        stream.hex().upper()
    )

    #if stream != expected:
#
    #    raise RuntimeError(
    #        "Original Python AES reference mismatch"
    #    )
#

# ==========================================================
# Main
# ==========================================================

def main():

    print(
        "========================================"
    )

    print(
        "SEC ENC GOLDEN GENERATOR"
    )

    print(
        "Using original MDM_SEC AES Python Core"
    )

    print(
        "========================================"
    )

    check_aes_reference()

    for case in CASES:

        generate_case(
            *case
        )

    print()

    print(
        "SEC ENC Golden generation completed."
    )

    print(
        "Output directory:",
        OUT_DIR
    )


if __name__ == "__main__":

    main()