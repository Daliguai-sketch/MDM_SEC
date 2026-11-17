#!/usr/bin/env python3
"""Generate deterministic AES-128 block vectors, with an optional independent oracle."""
import random
import sys
from pathlib import Path

sys.dont_write_bytecode = True
from reference_model import aes128

out = Path(sys.argv[1] if len(sys.argv) > 1 else "build/rtl/aes_vectors.txt")
out.parent.mkdir(parents=True, exist_ok=True)
rng = random.Random(0x128_50_05)

cases = [
    (bytes.fromhex("000102030405060708090a0b0c0d0e0f"),
     bytes.fromhex("00112233445566778899aabbccddeeff")),
    (bytes(16), bytes(16)),
    (bytes([255]) * 16, bytes([255]) * 16),
]
for _ in range(512):
    cases.append((rng.getrandbits(128).to_bytes(16, "big"),
                  rng.getrandbits(128).to_bytes(16, "big")))

try:
    from Crypto.Cipher import AES
except ImportError:
    AES = None
    print("PyCryptodome not installed: independent AES block cross-check skipped")

with out.open("w") as f:
    for key, block in cases:
        encrypted = aes128(key, block)
        if AES is not None:
            assert AES.new(key, AES.MODE_ECB).encrypt(block) == encrypted
        f.write(f"{key.hex()} {block.hex()} {encrypted.hex()}\n")

assert aes128(*cases[0]).hex() == "69c4e0d86a7b0430d8cdb78070b4c55a"
print(f"Generated {len(cases)} AES-128 block vectors: {out}")
if AES is not None:
    print("PASS independent PyCryptodome AES cross-check for every block")
