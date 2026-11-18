import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "testbench"))
sys.path.insert(0, str(ROOT / "sec_core" / "aes"))

from sec_core.aes import sec_aes_core_enc

from gen_aes_cmac_golden import (
    generate_mac_from_bytes
)


# ============================================================
# Configuration
# ============================================================

MODE_ENC_ONLY = 0
MODE_INT_ONLY = 1
MODE_INT2ENC  = 2
MODE_ENC2INT  = 3
MODE_PARALLEL = 4

ENC_KEY = bytes.fromhex(
    "F172263558DA301944A74CF383FD23A2"
)

#INT_KEY = bytes.fromhex(
#    "000102030405060708090A0B0C0D0E0F"
#)

INT_KEY = [
    0x00010203,
    0x04050607,
    0x08090A0B,
    0x0C0D0E0F
]

COUNT = 0x36AF6144
BEARER = 31
DIRECTION = 1

GOLDEN_DIR = ROOT / "rtl_gpt" / "tb" / "golden" / "sec_process_aes"

GOLDEN_DIR.mkdir(
    parents=True,
    exist_ok=True
)


# ============================================================
# Byte / Word Conversion
# ============================================================

def bytes_to_words128(data):

    if len(data) != 16:
        raise ValueError("Expected 16 bytes")

    return [
        int.from_bytes(data[i:i+4], "big")
        for i in range(0, 16, 4)
    ]


def words_to_bytes128(words):

    if len(words) != 4:
        raise ValueError(
            f"Expected 4 words, got {len(words)}"
        )

    return b"".join(
        (int(w) & 0xFFFFFFFF).to_bytes(4, "big")
        for w in words
    )


# ============================================================
# AES CTR
#
# Uses original MDM_SEC AES implementation.
# ============================================================

def aes_ctr_encrypt(
    key,
    count,
    bearer,
    direction,
    message
):

    if not message:
        return b""

    key_words = bytes_to_words128(key)

    round_keys = sec_aes_core_enc.aes_enc_key_exp(
        key_words
    )

    iv1 = (
        (bearer << 27) |
        (direction << 26)
    )

    result = bytearray()

    block_count = (len(message) + 15) // 16

    if block_count > 8192:
        raise ValueError(
            "AES CTR exceeds 13-bit counter range"
        )

    for block_index in range(block_count):

        iv = [
            count,
            iv1,
            0,
            block_index & 0x1FFF
        ]

        stream_words = sec_aes_core_enc.aes_enc_core(
            iv,
            round_keys
        )

        stream = words_to_bytes128(stream_words)

        start = block_index * 16

        block = message[start:start + 16]

        cipher_block = bytes(
            x ^ y
            for x, y in zip(block, stream)
        )

        result.extend(cipher_block)

    return bytes(result)


# ============================================================
# AES CMAC
# ============================================================

def aes_cmac(
    message
):

    return generate_mac_from_bytes(
        INT_KEY,
        COUNT,
        BEARER,
        DIRECTION,
        message
    )


# ============================================================
# Input Data
#
# Same pattern as the previous NULL Testbench.
# ============================================================

def generate_int_only_data(length):

    return bytes(
        (i + 0x31) & 0xFF
        for i in range(length)
    )


def generate_enc_data(length):

    return bytes(
        (i + 0xA5) & 0xFF
        for i in range(length)
    )


# ============================================================
# Five Mode Golden
# ============================================================

def calculate_golden(
    mode,
    int_only_data,
    enc_data
):

    cipher = b""
    int_message = b""
    mac = None

    if mode == MODE_ENC_ONLY:

        cipher = aes_ctr_encrypt(
            ENC_KEY,
            COUNT,
            BEARER,
            DIRECTION,
            enc_data
        )

    elif mode == MODE_INT_ONLY:

        int_message = (
            int_only_data +
            enc_data
        )

        mac = aes_cmac(int_message)

    elif mode == MODE_INT2ENC:

        int_message = (
            int_only_data +
            enc_data
        )

        mac = aes_cmac(int_message)

        mac_bytes = mac.to_bytes(
            4,
            "big"
        )

        enc_message = (
            enc_data +
            mac_bytes
        )

        cipher = aes_ctr_encrypt(
            ENC_KEY,
            COUNT,
            BEARER,
            DIRECTION,
            enc_message
        )

    elif mode == MODE_ENC2INT:

        cipher = aes_ctr_encrypt(
            ENC_KEY,
            COUNT,
            BEARER,
            DIRECTION,
            enc_data
        )

        int_message = (
            int_only_data +
            cipher
        )

        mac = aes_cmac(int_message)

    elif mode == MODE_PARALLEL:

        int_message = (
            int_only_data +
            enc_data
        )

        cipher = aes_ctr_encrypt(
            ENC_KEY,
            COUNT,
            BEARER,
            DIRECTION,
            enc_data
        )

        mac = aes_cmac(int_message)

    else:

        raise ValueError(
            f"Invalid mode: {mode}"
        )

    return {
        "cipher": cipher,
        "int_move": int_message,
        "mac": mac
    }


# ============================================================
# Golden File Writer
#
# 128-bit data:
#     One block per line.
#
# Last block:
#     Zero padded.
#
# MAC:
#     One 32-bit hexadecimal value.
# ============================================================

def write_data_hex(
    filename,
    data
):

    with open(filename, "w") as f:

        for offset in range(0, len(data), 16):

            block = data[offset:offset+16]

            block = block.ljust(
                16,
                b"\x00"
            )

            f.write(
                block.hex().upper() + "\n"
            )


def write_mac_hex(
    filename,
    mac
):

    with open(filename, "w") as f:

        if mac is not None:

            f.write(
                f"{mac:08X}\n"
            )


# ============================================================
# Test Cases
# ============================================================

TEST_CASES = [

    # mode, int_only_bytes, enc_bytes, int_move

    (MODE_ENC_ONLY, 0, 128, 0),

    (MODE_INT_ONLY, 13, 21, 1),

    (MODE_INT2ENC, 13, 21, 1),

    (MODE_ENC2INT, 13, 21, 1),

    (MODE_PARALLEL, 13, 21, 1),

    (MODE_INT2ENC, 5, 15, 1),

    (MODE_INT2ENC, 0, 16, 0),

    (MODE_ENC2INT, 5, 32, 1),

    (MODE_INT_ONLY, 0, 0, 1),

    (MODE_ENC_ONLY, 0, 0, 0),

    (MODE_PARALLEL, 13, 65, 1),

    (MODE_INT2ENC, 13, 128, 1),
]


# ============================================================
# Main
# ============================================================

def main():

    print(
        "Generating SEC PROCESS AES Golden..."
    )

    for test_id, case in enumerate(TEST_CASES):

        mode, int_len, enc_len, int_move = case

        int_only_data = generate_int_only_data(
            int_len
        )

        enc_data = generate_enc_data(
            enc_len
        )

        golden = calculate_golden(
            mode,
            int_only_data,
            enc_data
        )

        prefix = (
            GOLDEN_DIR /
            f"case_{test_id:02d}"
        )

        write_data_hex(
            f"{prefix}_cipher.hex",
            golden["cipher"]
        )

        write_data_hex(
            f"{prefix}_int_move.hex",
            golden["int_move"]
        )

        write_mac_hex(
            f"{prefix}_mac.hex",
            golden["mac"]
        )

        print(
            f"CASE={test_id:02d} "
            f"MODE={mode} "
            f"INT_ONLY={int_len} "
            f"ENC={enc_len} "
            f"CIPHER={len(golden['cipher'])} "
            f"INT_MOVE={len(golden['int_move'])} "
            f"MAC="
            f"{golden['mac']:08X}"
            if golden["mac"] is not None
            else
            f"CASE={test_id:02d} "
            f"MODE={mode} "
            f"CIPHER={len(golden['cipher'])} "
            f"MAC=NONE"
        )

    print(
        "SEC PROCESS AES Golden generation complete."
    )


if __name__ == "__main__":

    main()