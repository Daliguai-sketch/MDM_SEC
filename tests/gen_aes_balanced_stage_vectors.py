#!/usr/bin/env python3
"""Create AES intermediate-stage vectors using the repository's Python model."""
import random
import sys
from pathlib import Path

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from sec_core.aes import sec_aes_core_enc as aes


def to_rows(data):
    # The RTL and Python models use column-major AES state, MSB first.
    return [[data[4 * col + row] for col in range(4)] for row in range(4)]


def from_rows(rows):
    return bytes(rows[row][col] for col in range(4) for row in range(4))


def next_key(key, rcon):
    # Use the Python model's RotWord and SubWord, not the RTL's factored
    # second-key equations, so the two implementations are independent.
    old = [int.from_bytes(key[i:i + 4], "big") for i in range(0, 16, 4)]
    temp = aes.sub_word(aes.rot_word(old[3])) ^ (rcon << 24)
    new = []
    for word in old:
        temp ^= word
        new.append(temp)
    return b"".join(word.to_bytes(4, "big") for word in new)


def xor_bytes(a, b):
    return bytes(x ^ y for x, y in zip(a, b))


def vectors(state, key, rcon, last):
    rows = to_rows(state)
    aes.sub_bytes(rows)
    sub = from_rows(rows)
    aes.shift_rows(rows)
    shifted = from_rows(rows)
    aes.mix_columns(rows)
    mixed = from_rows(rows)
    key1 = next_key(key, rcon)
    rcon2 = aes.xtime(rcon)
    key2 = next_key(key1, rcon2)
    return (state.hex(), key.hex(), f"{rcon:02x}", f"{rcon2:02x}", str(last),
            sub.hex(), shifted.hex(), mixed.hex(), xor_bytes(mixed, key1).hex(),
            xor_bytes(shifted, key1).hex(), key1.hex(), key2.hex())


def main():
    out = Path(sys.argv[1] if len(sys.argv) > 1 else "build/rtl/aes_balanced_stage_vectors.txt")
    out.parent.mkdir(parents=True, exist_ok=True)
    key = bytes.fromhex("000102030405060708090a0b0c0d0e0f")
    state = bytes.fromhex("00102030405060708090a0b0c0d0e0f0")
    fips = vectors(state, key, 1, 0)
    assert fips[5:9] == (
        "63cab7040953d051cd60e0e7ba70e18c",
        "6353e08c0960e104cd70b751bacad0e7",
        "5f72641557f5bc92f7be3b291db9f91a",
        "89d810e8855ace682d1843d8cb128fe4",
    ), "FIPS-197 intermediate state cross-check failed"
    assert fips[10:] == (
        "d6aa74fdd2af72fadaa678f1d6ab76fe",
        "b692cf0b643dbdf1be9bc5006830b3fe",
    ), "FIPS-197 expanded key cross-check failed"

    # Exercise all 256 Rcon values, with new state/key for each, and verify
    # both the ordinary and bypassed final round for every combination.
    rng = random.Random(0xA35_BA1A)
    cases = [(state, key, 1), (bytes(16), bytes(16), 0),
             (bytes([255]) * 16, bytes([255]) * 16, 0xff)]
    cases += [(rng.getrandbits(128).to_bytes(16, "big"),
               rng.getrandbits(128).to_bytes(16, "big"), rcon)
              for rcon in range(256)]
    with out.open("w", encoding="ascii") as stream:
        for state, key, rcon in cases:
            for last in (0, 1):
                stream.write(" ".join(vectors(state, key, rcon, last)) + "\n")
    print(f"Generated {len(cases) * 2} Python-model AES intermediate-stage vectors: {out}")


if __name__ == "__main__":
    main()
