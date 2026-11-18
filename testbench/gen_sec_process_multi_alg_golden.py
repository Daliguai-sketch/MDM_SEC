import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "testbench"))

from gen_sec_process_golden import (
    aes_ctr_encrypt,
    generate_int_only_data,
    generate_enc_data,
)

from gen_aes_cmac_golden import (
    generate_mac_from_bytes
)

from gen_snow3g_golden import (
    generate_snow3g_stream
)

from gen_zuc_golden import (
    generate_zuc_stream
)

from gen_snow3g_mac_golden import (
    generate_mac as snow3g_mac
)

from gen_zuc_mac_golden import (
    generate_mac as zuc_mac
)


# ============================================================
# Algorithm Encoding
# ============================================================

ALG_AES  = 0
ALG_SNOW = 1
ALG_ZUC  = 2
ALG_NULL = 3


# ============================================================
# Mode Encoding
# ============================================================

MODE_ENC_ONLY = 0
MODE_INT_ONLY = 1
MODE_INT2ENC  = 2
MODE_ENC2INT  = 3
MODE_PARALLEL = 4


# ============================================================
# Configuration
# ============================================================

COUNT = 0x36AF6144
BEARER = 31
DIRECTION = 1

AES_ENC_KEY = bytes.fromhex(
    "F172263558DA301944A74CF383FD23A2"
)

AES_INT_KEY = [
    0x00010203,
    0x04050607,
    0x08090A0B,
    0x0C0D0E0F
]

STREAM_KEY = [
    0x4881FF48,
    0x952C4910,
    0x82C5B300,
    0xABD6459F
]


OUTPUT_DIR = (
    ROOT /
    "rtl_gpt" /
    "tb" /
    "golden" /
    "sec_process_multi_alg"
)

OUTPUT_DIR.mkdir(
    parents=True,
    exist_ok=True
)


# ============================================================
# IV
# ============================================================

def generate_enc_iv(
    count,
    bearer,
    direction
):

    iv_word = (
        (bearer << 27) |
        (direction << 26)
    )

    return [
        iv_word,
        count,
        iv_word,
        count
    ]


# ============================================================
# Keystream Conversion
# ============================================================

def stream_words_to_bytes(words):

    return b"".join(
        (int(word) & 0xFFFFFFFF).to_bytes(4, "big")
        for word in words
    )


# ============================================================
# ENC
# ============================================================

def encrypt(
    algorithm,
    message
):

    if algorithm == ALG_NULL:
        return message

    if not message:
        return b""

    if algorithm == ALG_AES:

        return aes_ctr_encrypt(
            AES_ENC_KEY,
            COUNT,
            BEARER,
            DIRECTION,
            message
        )

    iv = generate_enc_iv(
        COUNT,
        BEARER,
        DIRECTION
    )

    word_num = (
        len(message) + 3
    ) // 4

    if algorithm == ALG_SNOW:

        words = generate_snow3g_stream(
            STREAM_KEY,
            iv,
            word_num
        )

    elif algorithm == ALG_ZUC:

        words = generate_zuc_stream(
            STREAM_KEY,
            iv,
            word_num
        )

    else:

        raise ValueError(
            f"Invalid ENC algorithm: {algorithm}"
        )

    stream = stream_words_to_bytes(words)

    return bytes(
        a ^ b
        for a, b in zip(message, stream)
    )


# ============================================================
# INT
# ============================================================

def calculate_mac(
    algorithm,
    message
):

    if algorithm == ALG_NULL:
        return 0

    if algorithm == ALG_AES:

        return generate_mac_from_bytes(
            AES_INT_KEY,
            COUNT,
            BEARER,
            DIRECTION,
            message
        )

    if algorithm == ALG_SNOW:

        return snow3g_mac(
            STREAM_KEY,
            COUNT,
            BEARER,
            DIRECTION,
            message
        )

    if algorithm == ALG_ZUC:

        return zuc_mac(
            STREAM_KEY,
            COUNT,
            BEARER,
            DIRECTION,
            message
        )

    raise ValueError(
        f"Invalid INT algorithm: {algorithm}"
    )


# ============================================================
# Five Modes
# ============================================================

def calculate_golden(
    mode,
    enc_algorithm,
    int_algorithm,
    int_only_data,
    enc_data
):

    cipher = b""
    int_message = b""
    mac = None

    if mode == MODE_ENC_ONLY:

        cipher = encrypt(
            enc_algorithm,
            enc_data
        )

    elif mode == MODE_INT_ONLY:

        int_message = (
            int_only_data +
            enc_data
        )

        mac = calculate_mac(
            int_algorithm,
            int_message
        )

    elif mode == MODE_INT2ENC:

        int_message = (
            int_only_data +
            enc_data
        )

        mac = calculate_mac(
            int_algorithm,
            int_message
        )

        enc_message = (
            enc_data +
            mac.to_bytes(4, "big")
        )

        cipher = encrypt(
            enc_algorithm,
            enc_message
        )

    elif mode == MODE_ENC2INT:

        cipher = encrypt(
            enc_algorithm,
            enc_data
        )

        int_message = (
            int_only_data +
            cipher
        )

        mac = calculate_mac(
            int_algorithm,
            int_message
        )

    elif mode == MODE_PARALLEL:

        cipher = encrypt(
            enc_algorithm,
            enc_data
        )

        int_message = (
            int_only_data +
            enc_data
        )

        mac = calculate_mac(
            int_algorithm,
            int_message
        )

    else:

        raise ValueError(
            f"Invalid mode: {mode}"
        )

    return cipher, int_message, mac


# ============================================================
# Golden Writer
# ============================================================

def write_data_hex(path, data):

    with open(path, "w") as f:

        for offset in range(0, len(data), 16):

            block = data[offset:offset + 16]

            block = block.ljust(
                16,
                b"\x00"
            )

            f.write(
                block.hex().upper() + "\n"
            )


def write_mac_hex(path, mac):

    with open(path, "w") as f:

        if mac is not None:

            f.write(
                f"{mac:08X}\n"
            )


# ============================================================
# Test Cases
# ============================================================

TEST_CASES = [

    # MODE, INT_ONLY_BYTES, ENC_BYTES, INT_MOVE

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

    algorithms = [
        ALG_AES,
        ALG_SNOW,
        ALG_ZUC,
        ALG_NULL
    ]

    for enc_alg in algorithms:

        for int_alg in algorithms:

            for test_id, case in enumerate(TEST_CASES):

                mode, int_len, enc_len, int_move = case

                int_only_data = generate_int_only_data(
                    int_len
                )

                enc_data = generate_enc_data(
                    enc_len
                )

                cipher, int_message, mac = calculate_golden(
                    mode,
                    enc_alg,
                    int_alg,
                    int_only_data,
                    enc_data
                )

                prefix = (
                    OUTPUT_DIR /
                    f"e{enc_alg}_i{int_alg}_case_{test_id:02d}"
                )

                write_data_hex(
                    f"{prefix}_cipher.hex",
                    cipher
                )

                write_data_hex(
                    f"{prefix}_int_move.hex",
                    int_message
                )

                write_mac_hex(
                    f"{prefix}_mac.hex",
                    mac
                )

                print(
                    f"ENC={enc_alg} "
                    f"INT={int_alg} "
                    f"TEST={test_id:02d} "
                    f"MODE={mode} "
                    f"CIPHER={len(cipher)} "
                    f"INT_MOVE={len(int_message)} "
                    f"MAC={mac if mac is not None else 'NONE'}"
                )

    print(
        "SEC PROCESS MULTI-ALG GOLDEN GENERATION COMPLETE"
    )


if __name__ == "__main__":

    main()