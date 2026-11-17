#!/usr/bin/env python3
"""Independent packet vectors for the full 16-bit byte-count limit."""
import random
import sys
from pathlib import Path

sys.dont_write_bytecode = True
from reference_model import cipher, integrity, packet

OUT = Path(sys.argv[1] if len(sys.argv) > 1 else "build/rtl/boundary_vectors.txt")
OUT.parent.mkdir(parents=True, exist_ok=True)
rng = random.Random(0x65535_128)


def randbytes(n):
    return bytes(rng.randrange(256) for _ in range(n))


def beat_words(buf):
    for i in range(0, len(buf), 16):
        yield int.from_bytes(buf[i:i+16].ljust(16, b"\0"), "big")


# All valid cases approach the architectural limit. In particular, the
# B+MAC result for the two mode-2 cases is exactly 65535 bytes; one has an
# unaligned A/B boundary and the other has A+B exactly 65535 as well.
specs = [
    (0, 2, 0, 0, 65535, False),       # AES byte count must not wrap
    (2, 2, 2, 4, 65531, False),       # maximum A+B and B+MAC
    (2, 2, 3, 3, 65531, False),       # unaligned A and B/MAC boundary
    (3, 3, 1, 1, 65534, False),       # int(A||cipher(B)), unaligned split
    (1, 0, 3, 65535, 0, False),       # maximum all-A integrity
    (4, 1, 2, 5, 65530, False),       # simultaneous lanes
    (3, 1, 2, 32767, 32768, False),   # large unaligned A and B
    (5, 2, 2, 0, 65535, False),       # decrypt 65535 bytes, matching MAC
    (5, 2, 2, 0, 65535, True),        # same limit, corrupted MAC
    (5, 3, 1, 1, 65534, False),       # unaligned A/B and final MAC
    (5, 1, 3, 14, 65521, False),      # MAC crosses a 128-bit boundary
    (5, 2, 3, 65531, 4, False),       # empty payload and maximum A
]
cases = []
for mode, ca, ia, alen, blen, corrupt in specs:
    ck = randbytes(16)
    ik = randbytes(16)
    count = rng.getrandbits(32)
    bearer = rng.randrange(32)
    direction = rng.randrange(2)
    a = randbytes(alen)
    if mode == 5:
        payload = randbytes(blen-4)
        expected_mac = integrity(ia, ik, count, bearer, direction, a+payload)
        b = cipher(ca, ck, count, bearer, direction, payload+expected_mac.to_bytes(4, "big"))
        if corrupt:
            b = b[:-1]+bytes([b[-1] ^ 1])
    else:
        b = randbytes(blen)
    mac, valid, out, rx, rx_valid, match = packet(mode, ca, ia, ck, ik, count, bearer, direction, a, b)
    if mode == 5:
        assert out == payload and mac == expected_mac
        assert rx == (expected_mac ^ int(corrupt)) and match == (not corrupt)
    assert len(a) + len(b) <= 65535
    assert len(out) <= 65535
    cases.append((mode, ca, ia, ck, ik, count, bearer, direction, a, b,
                  mac, valid, out, rx, rx_valid, match))

# AES CTR and CMAC are additionally checked against an independent library
# when available; the test suite does not require this optional dependency.
try:
    from Crypto.Cipher import AES
    from Crypto.Hash import CMAC
except ImportError:
    print("PyCryptodome not installed: optional large-vector AES cross-check skipped")
else:
    for mode, ca, ia, ck, ik, count, bearer, direction, a, b, mac, _, out, rx, _, match in cases:
        prefix = count.to_bytes(4, "big") + bytes([(bearer << 3) | (direction << 2), 0, 0, 0])
        if mode != 0 and ia == 2:
            mac_input = a + (out if mode in (3, 5) else b)
            checker = CMAC.new(ik, ciphermod=AES)
            checker.update(prefix + mac_input)
            assert mac == int.from_bytes(checker.digest()[:4], "big")
        if mode != 1 and ca == 2:
            checker = AES.new(ck, AES.MODE_CTR, nonce=prefix, initial_value=0)
            if mode == 5:
                decrypted = checker.decrypt(b)
                assert decrypted[:-4] == out and int.from_bytes(decrypted[-4:], "big") == rx
                assert (rx == mac) == match
            else:
                cipher_input = b + (mac.to_bytes(4, "big") if mode == 2 else b"")
                assert out == checker.encrypt(cipher_input)
    print("PASS independent PyCryptodome AES cross-check at the 65535-byte limit")

with OUT.open("w") as f:
    for idx, (mode, ca, ia, ck, ik, count, bearer, direction, a, b, mac, valid, ct, rx, rx_valid, match) in enumerate(cases):
        f.write(f"{idx} {mode} {ca} {ia} {ck.hex()} {ik.hex()} {count:08x} "
                f"{bearer} {direction} {len(a)} {len(b)} {mac:08x} {int(valid)} {len(ct)} "
                f"{rx:08x} {int(rx_valid)} {int(match)}\n")
        for segment in (a, b, ct):
            for word in beat_words(segment):
                f.write(f"{word:032x}\n")
print(f"Generated {len(cases)} full-range boundary cases: {OUT}")
