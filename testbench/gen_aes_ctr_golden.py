from sec_core.aes import sec_aes_core_enc


def comb_128block(words):
    result = 0

    for word in words:
        result = (result << 32) | word

    return result


def gen_aes_ctr_stream(
    key,
    count,
    bearer,
    direction,
    stream_num
):

    round_keys = sec_aes_core_enc.aes_enc_key_exp(key)

    iv1 = (
        (bearer << 27)
        | (direction << 26)
    )

    for i in range(stream_num):

        iv = [
            count,
            iv1,
            0,
            i & 0x1FFF
        ]

        stream = sec_aes_core_enc.aes_enc_core(
            iv,
            round_keys
        )

        stream128 = comb_128block(stream)

        print(
            f"expected_stream[{i}] = "
            f"128'h{stream128:032X};"
        )


if __name__ == "__main__":

    key = [
        0x4881FF48,
        0x952C4910,
        0x82C5B300,
        0xABD6459F
    ]

    key = [        
        0xF1722635,
        0x58DA3019,
        0x44A74CF3,
        0x83FD23A2 
    ]              

    gen_aes_ctr_stream(
        key=key,
        count=0x36AF6144,
        bearer=0x1F,
        direction=1,
        stream_num=6
    )