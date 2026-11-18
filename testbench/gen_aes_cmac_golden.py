import os
import sys

# ============================================================
# Project Path
# ============================================================

PROJECT_ROOT = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..")
)

sys.path.insert(0, PROJECT_ROOT)

from sec_core.aes.sec_aes_ctrl import fun_gen_mac
from src.sec_class_define import data_desc


# ============================================================
# Test Parameters
# ============================================================

KEY0 = [
    0xF1722635,
    0x58DA3019,
    0x44A74CF3,
    0x83FD23A2
]

KEY1 = [
    0x00010203,
    0x04050607,
    0x08090A0B,
    0x0C0D0E0F
]

COUNT0 = 0x36AF6144

BEARER = 0x1F
DIRECTION = 0


# ============================================================
# Byte -> 32-bit Words
# ============================================================

def bytes_to_words(data_bytes):

    words = []

    for offset in range(0, len(data_bytes), 4):

        chunk = data_bytes[offset:offset+4]

        # Padding only for word alignment.
        # CMAC Padding is handled inside fun_gen_mac().

        chunk = chunk + bytes(4-len(chunk))

        word = int.from_bytes(
            chunk,
            byteorder="big"
        )

        words.append(word)

    return words


# ============================================================
# Generate One Golden MAC
# ============================================================

def generate_mac(
    key,
    count,
    msg_len
):

    # Same data pattern as Verilog Testbench:
    #
    # 00 01 02 ... FF 00 01 ...

    data_bytes = bytes(
        i & 0xFF
        for i in range(msg_len)
    )
    return generate_mac_from_bytes(
        key=key,
        count=count,
        bearer=BEARER,
        direction=DIRECTION,
        message=data_bytes
    )

def generate_mac_from_bytes(
    key,
    count,
    bearer,
    direction,
    message
):
    """
    Generate AES-CMAC using actual message bytes.

    Args:
        key:
            Same key format as existing generate_mac().

        count:
            32-bit COUNT.

        bearer:
            5-bit BEARER.

        direction:
            1-bit DIRECTION.

        message:
            bytes or bytearray.

    Returns:
        32-bit MAC integer.
    """

    if not isinstance(message, (bytes, bytearray)):
        raise TypeError(
            "message must be bytes or bytearray"
        )

    words = bytes_to_words(message)

    valid = [1] * len(words)
    last = [0] * len(words)

    if last:
        last[-1] = 1

    int_data = data_desc(
        words,
        valid,
        last,
        len(message)
    )

    mac_data = data_desc(
        [],
        [],
        [],
        0
    )

    int_iv = [
        count,
        (bearer << 27) | (direction << 26)
    ]

    fun_gen_mac(
        int_iv,
        key,
        int_data,
        mac_data
    )

    if not mac_data.data:
        raise RuntimeError(
            "AES-CMAC generation failed: "
            f"len={len(message)}, "
            f"count={count:08X}"
        )

    return mac_data.data[0] & 0xFFFFFFFF


# ============================================================
# Build Test Cases
# ============================================================

def build_test_cases():

    cases = []

    # --------------------------------------------------------
    # Golden 0~12
    # TEST0: Basic
    # --------------------------------------------------------

    basic_lengths = [
        0, 1, 7, 8, 9,
        15, 16, 17, 24, 32,
        64, 128, 4096
    ]

    for length in basic_lengths:

        cases.append({
            "key": KEY0,
            "count": COUNT0,
            "length": length,
            "description": f"BASIC_LEN_{length}"
        })

    # --------------------------------------------------------
    # Golden 13~16
    # TEST4: Multi-message
    # --------------------------------------------------------

    multi_messages = [
        (128,  0x36AF6144),
        (4096, 0x36AF6145),
        (24,   0x36AF6146),
        (0,    0x36AF6147)
    ]

    for length, count in multi_messages:

        cases.append({
            "key": KEY0,
            "count": count,
            "length": length,
            "description": f"MULTI_LEN_{length}"
        })

    # --------------------------------------------------------
    # Golden 17~18
    # TEST5: Key Update
    # --------------------------------------------------------

    cases.append({
        "key": KEY0,
        "count": COUNT0,
        "length": 128,
        "description": "KEY_UPDATE_KEY0"
    })

    cases.append({
        "key": KEY1,
        "count": COUNT0,
        "length": 128,
        "description": "KEY_UPDATE_KEY1"
    })

    # --------------------------------------------------------
    # Golden 19~21
    # TEST6: Key0 -> Key1 -> Key0
    # --------------------------------------------------------

    cases.append({
        "key": KEY0,
        "count": COUNT0,
        "length": 128,
        "description": "KEY_SWITCH_KEY0"
    })

    cases.append({
        "key": KEY1,
        "count": COUNT0,
        "length": 128,
        "description": "KEY_SWITCH_KEY1"
    })

    cases.append({
        "key": KEY0,
        "count": COUNT0,
        "length": 128,
        "description": "KEY_SWITCH_BACK_KEY0"
    })

    return cases


# ============================================================
# Main
# ============================================================

def main():

    cases = build_test_cases()

    output_dir = os.path.join(
        PROJECT_ROOT,
        "rtl_gpt",
        "tb",
        "golden"
    )

    os.makedirs(
        output_dir,
        exist_ok=True
    )

    output_file = os.path.join(
        output_dir,
        "aes_cmac_golden.hex"
    )

    print("======================================")
    print("AES-CMAC Golden Generator")
    print("======================================")

    golden_values = []

    for index, case in enumerate(cases):

        mac = generate_mac(
            key=case["key"],
            count=case["count"],
            msg_len=case["length"]
        )

        golden_values.append(mac)

        print(
            f"[{index:02d}] "
            f"{case['description']:<25} "
            f"COUNT=0x{case['count']:08X} "
            f"LEN={case['length']:4d} "
            f"MAC=0x{mac:08X}"
        )

    # --------------------------------------------------------
    # Write HEX
    # --------------------------------------------------------

    with open(
        output_file,
        "w",
        encoding="utf-8"
    ) as f:

        for mac in golden_values:
            f.write(f"{mac:08X}\n")

    print()
    print("======================================")
    print(f"Generated {len(golden_values)} Golden MACs")
    print(f"Output: {output_file}")
    print("======================================")


if __name__ == "__main__":
    main()