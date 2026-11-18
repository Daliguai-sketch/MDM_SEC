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


KEY1 = [
    0x00010203,
    0x04050607,
    0x08090A0B,
    0x0C0D0E0F
]

COUNT0 = 0x36AF6144

BEARER = 0x1F
DIRECTION = 1


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
# Main
# ============================================================

def main():

    mac = generate_mac(       
        key=KEY1,      
        count=COUNT0,  
        msg_len=0
    )                            
    
    if __name__ == "__main__":
    main()