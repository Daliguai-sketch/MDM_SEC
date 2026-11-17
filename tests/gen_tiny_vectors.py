#!/usr/bin/env python3
"""Exercise the minimum buffer parameter with every mode and algorithm pair."""
import random
import sys
from pathlib import Path

sys.dont_write_bytecode = True
from reference_model import packet

OUT = Path(sys.argv[1] if len(sys.argv) > 1 else "build/rtl/tiny_vectors.txt")
OUT.parent.mkdir(parents=True, exist_ok=True)
rng = random.Random(0x128_0001)


def randbytes(n):
    return bytes(rng.randrange(256) for _ in range(n))


def beat_words(buf):
    for i in range(0, len(buf), 16):
        yield int.from_bytes(buf[i:i+16].ljust(16, b"\0"), "big")


with OUT.open("w") as f:
    idx = 0
    for mode in range(5):
        for ca in range(4):
            for ia in range(4):
                for alen, blen in ((0, 0), (0, 1), (1, 0)):
                    ck = randbytes(16)
                    ik = randbytes(16)
                    count = rng.getrandbits(32)
                    bearer = rng.randrange(32)
                    direction = rng.randrange(2)
                    a = randbytes(alen)
                    b = randbytes(blen)
                    mac, valid, ct, rx, rx_valid, match = packet(
                        mode, ca, ia, ck, ik, count, bearer, direction, a, b)
                    f.write(f"{idx} {mode} {ca} {ia} {ck.hex()} {ik.hex()} {count:08x} "
                            f"{bearer} {direction} {alen} {blen} {mac:08x} {int(valid)} {len(ct)} "
                            f"{rx:08x} {int(rx_valid)} {int(match)}\n")
                    for segment in (a, b, ct):
                        for word in beat_words(segment):
                            f.write(f"{word:032x}\n")
                    idx += 1
print(f"Generated {idx} minimum-capacity packet cases: {OUT}")
