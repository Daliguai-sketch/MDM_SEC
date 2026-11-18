import os
import sys

PROJECT_ROOT = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..")
)

sys.path.insert(0, PROJECT_ROOT)

from sec_core.snow3g import sec_snow3g_core as snow


KEY = [
    0x4881FF48,
    0x952C4910,
    0x82C5B300,
    0xABD6459F
]

IV = [
    0xF8000000,
    0x36AF6144,
    0xF8000000,
    0x36AF6144
]

WORD_NUM = 2048

def main():

    s = [0] * 16
    r = [0] * 3

    snow.init_parameters(KEY, IV, s, r)

    w = 0

    # 32 init iterations
    for _ in range(32):
        zt, w, s, r = snow.snow_3g_core(
            1, w, s, r
        )

    # Discard first word
    zt, w, s, r = snow.snow_3g_core(
        0, w, s, r
    )

    streams = []

    # Generate 256 words
    
    for _ in range(WORD_NUM):

        zt, w, s, r = snow.snow_3g_core(
            0, w, s, r
        )

        streams.append(zt)

    output_dir = os.path.join(
        PROJECT_ROOT,
        "rtl_gpt",
        "tb",
        "golden"
    )

    os.makedirs(output_dir, exist_ok=True)

    output_file = os.path.join(
        output_dir,
        "snow3g_stream.hex"
    )

    with open(output_file, "w") as f:

        for word in streams:
            f.write(f"{word:08X}\n")

    print(
        f"Generated {len(streams)} SNOW3G words"
    )

    print("Output:", output_file)


    output_file_128 = os.path.join(
        output_dir,            
        "snow3g_stream128.hex"    
    )                          

    with open(
        output_file_128,
        "w",
        encoding="utf-8"
    ) as f:

        for i in range(len(streams) // 4):

            block = (
                (streams[4 * i + 0] << 96)
                | (streams[4 * i + 1] << 64)
                | (streams[4 * i + 2] << 32)
                | streams[4 * i + 3]
            )

            f.write(f"{block:032X}\n")

def generate_snow3g_stream(key, iv, word_num):
    """
    Generate SNOW3G 32-bit keystream words.

    Args:
        key:      Four 32-bit words.
        iv:       Four 32-bit words.
        word_num: Number of output words.

    Returns:
        List of 32-bit integers.
    """

    s = [0] * 16
    r = [0] * 3

    snow.init_parameters(key, iv, s, r)

    w = 0

    # 32 initialization iterations
    for _ in range(32):
        zt, w, s, r = snow.snow_3g_core(
            1, w, s, r
        )

    # Discard first word
    zt, w, s, r = snow.snow_3g_core(
        0, w, s, r
    )

    streams = []

    for _ in range(word_num):
        zt, w, s, r = snow.snow_3g_core(
            0, w, s, r
        )

        streams.append(zt & 0xFFFFFFFF)

    return streams

def generate_enc_iv(count, bearer, direction):
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

def stream_cipher_encrypt(
    algorithm,
    key,
    count,
    bearer,
    direction,
    message
):
    if not message:
        return b""

    word_num = (len(message) + 3) // 4

    iv = generate_enc_iv(
        count,
        bearer,
        direction
    )

    if algorithm == 1:
        words = generate_snow3g_stream(
            key,
            iv,
            word_num
        )

    #elif algorithm == 2:
    #    words = generate_zuc_stream(
    #        key,
    #        iv,
    #        word_num
    #    )

    else:
        raise ValueError(
            f"Unsupported algorithm: {algorithm}"
        )

    keystream = stream_words_to_bytes(words)

    return bytes(
        a ^ b
        for a, b in zip(message, keystream)
    )

def stream_words_to_bytes(words):
    return b"".join(
        (word & 0xFFFFFFFF).to_bytes(4, "big")
        for word in words
    )

if __name__ == "__main__":
    main()