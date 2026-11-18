import random

from sec_core.snow3g import sec_snow3g_core as snow

def main():
    random.seed(1234)

    with open("tb/golden/snow3g_sbox_vectors.hex", "w") as f:

        for _ in range(1000):

            x = random.getrandbits(32)

            s1 = snow.S1(x)
            s2 = snow.S2(x)

            f.write(
                f"{x:08X} {s1:08X} {s2:08X}\n"
            )