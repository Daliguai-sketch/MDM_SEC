#!/usr/bin/env python3

import os
import sys

from Crypto.Cipher import AES

PROJECT_ROOT = os.path.abspath(                  
    os.path.join(os.path.dirname(__file__), "..")
)                                                
                                                                                                 
sys.path.insert(0, PROJECT_ROOT)                 

GOLDEN_DIR = os.path.join(PROJECT_ROOT, "rtl_gpt", "tb", "golden")
OUT_DIR = os.path.join(PROJECT_ROOT, "rtl_gpt", "tb", "golden", "sec_enc")

os.makedirs(OUT_DIR, exist_ok=True)


ALG_AES = 0
ALG_SNOW = 1
ALG_ZUC = 2
ALG_NULL = 3


KEY_AES = bytes.fromhex(
    "F172263558DA301944A74CF383FD23A2"
)

KEY_STREAM = bytes.fromhex(
    "4881FF48952C491082C5B300ABD6459F"
)

KEY_AES_1 = bytes.fromhex(
    "000102030405060708090A0B0C0D0E0F"
)


COUNT0 = 0x36AF6144
COUNT1 = 0x12345678

BEARER0 = 31
BEARER1 = 7

DIRECTION0 = 1
DIRECTION1 = 0


def make_plaintext(length):

    return bytes(
        i & 0xFF
        for i in range(length)
    )


def aes_ctr_keystream(
    key,
    count,
    bearer,
    direction,
    length
):

    aes = AES.new(
        key,
        AES.MODE_ECB
    )

    block_count = (length + 15) // 16

    if block_count > 8192:
        raise ValueError(
            "AES CTR exceeds 13-bit counter space"
        )

    result = bytearray()

    for counter in range(block_count):

        block = (
            count.to_bytes(4, "big")
            +
            (
                (bearer << 27)
                |
                (direction << 26)
            ).to_bytes(4, "big")
            +
            bytes(4)
            +
            counter.to_bytes(4, "big")
        )

        result.extend(
            aes.encrypt(block)
        )

    return bytes(result[:length])


def load_stream_words(path):

    words = []

    with open(path, "r") as f:

        for line in f:

            line = line.strip()

            if not line:
                continue

            if line.startswith("#"):
                continue

            words.append(
                int(line, 16)
            )

    result = bytearray()

    for word in words:

        result.extend(
            word.to_bytes(4, "big")
        )

    return bytes(result)


SNOW_STREAM = load_stream_words(
    os.path.join(
        GOLDEN_DIR,
        "snow3g_stream.hex"
    )
)

ZUC_STREAM = load_stream_words(
    os.path.join(
        GOLDEN_DIR,
        "zuc_stream.hex"
    )
)


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

    if alg == ALG_SNOW:

        assert key == KEY_STREAM
        assert count == COUNT0
        assert bearer == BEARER0
        assert direction == DIRECTION0

        if len(SNOW_STREAM) < length:
            raise ValueError(
                "SNOW3G Golden stream too short"
            )

        return SNOW_STREAM[:length]

    if alg == ALG_ZUC:

        assert key == KEY_STREAM
        assert count == COUNT0
        assert bearer == BEARER0
        assert direction == DIRECTION0

        if len(ZUC_STREAM) < length:
            raise ValueError(
                "ZUC Golden stream too short"
            )

        return ZUC_STREAM[:length]

    if alg == ALG_NULL:

        return bytes(length)

    raise ValueError("Invalid algorithm")


def generate_case(
    case_id,
    alg,
    length,
    key,
    count,
    bearer,
    direction
):

    plaintext = make_plaintext(length)

    keystream = get_keystream(
        alg,
        key,
        count,
        bearer,
        direction,
        length
    )

    cipher = bytes(
        a ^ b
        for a, b in zip(
            plaintext,
            keystream
        )
    )

    block_count = (length + 15) // 16

    path = os.path.join(
        OUT_DIR,
        "case_%02d.hex" % case_id
    )

    with open(path, "w") as f:

        for block_index in range(block_count):

            start = block_index * 16
            end = start + 16

            block = cipher[start:end]

            block = block.ljust(
                16,
                b"\x00"
            )

            f.write(
                block.hex().upper() + "\n"
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


CASES = [

    # TEST0: AES 128B
    (0, ALG_AES, 128,
     KEY_AES, COUNT0, BEARER0, DIRECTION0),

    # TEST1: SNOW3G 128B
    (1, ALG_SNOW, 128,
     KEY_STREAM, COUNT0, BEARER0, DIRECTION0),

    # TEST2: ZUC 128B
    (2, ALG_ZUC, 128,
     KEY_STREAM, COUNT0, BEARER0, DIRECTION0),

    # TEST3: NULL 128B
    (3, ALG_NULL, 128,
     KEY_AES, COUNT0, BEARER0, DIRECTION0),

    # TEST4: 508B cipher region
    (4, ALG_AES, 508,
     KEY_AES, COUNT0, BEARER0, DIRECTION0),

    # TEST5: input bubbles
    (5, ALG_SNOW, 512,
     KEY_STREAM, COUNT0, BEARER0, DIRECTION0),

    # TEST6: output backpressure
    (6, ALG_ZUC, 512,
     KEY_STREAM, COUNT0, BEARER0, DIRECTION0),

    # TEST7: algorithm switching
    (7, ALG_AES, 128,
     KEY_AES, COUNT0, BEARER0, DIRECTION0),

    (8, ALG_SNOW, 128,
     KEY_STREAM, COUNT0, BEARER0, DIRECTION0),

    (9, ALG_ZUC, 128,
     KEY_STREAM, COUNT0, BEARER0, DIRECTION0),

    (10, ALG_NULL, 128,
     KEY_AES, COUNT0, BEARER0, DIRECTION0),

    # TEST8: key/count update
    (11, ALG_AES, 256,
     KEY_AES_1, COUNT1, BEARER1, DIRECTION1),

    (12, ALG_AES, 256,
     KEY_AES, COUNT0, BEARER0, DIRECTION0),

    # TEST9: zero byte
    (13, ALG_NULL, 0,
     KEY_AES, COUNT0, BEARER0, DIRECTION0),

    # TEST10: 4096B
    (14, ALG_AES, 4096,
     KEY_AES, COUNT0, BEARER0, DIRECTION0),

    (15, ALG_SNOW, 4096,
     KEY_STREAM, COUNT0, BEARER0, DIRECTION0),

    (16, ALG_ZUC, 4096,
     KEY_STREAM, COUNT0, BEARER0, DIRECTION0),

    # TEST11: valid/ready stability
    (17, ALG_ZUC, 1024,
     KEY_STREAM, COUNT0, BEARER0, DIRECTION0),

]


def main():

    for case in CASES:

        generate_case(*case)

    print()
    print("SEC ENC Golden generation completed.")


if __name__ == "__main__":

    main()