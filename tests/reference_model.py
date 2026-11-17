"""Byte-oriented 3GPP EEA/EIA reference for the RTL regression.

The existing repository's Python primitives are used with their word-order
convention corrected at the boundary. The packet composition and MAC modes
below are independent of the RTL. Published fixed vectors in gen_vectors.py
and optional PyCryptodome comparisons keep the oracle from being self-only.
"""
from functools import lru_cache
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from sec_core.aes import sec_aes_core_enc as aes
from sec_core.snow3g import sec_snow3g_core as snow
from sec_core.zuc import sec_zuc_core as zuc

MASK32 = (1 << 32) - 1
MASK64 = (1 << 64) - 1
MASK128 = (1 << 128) - 1


def words(b):
    return [int.from_bytes(b[i:i + 4], "big") for i in range(0, len(b), 4)]


@lru_cache(maxsize=32)
def _aes_schedule(key):
    return aes.aes_enc_key_exp(words(key)[::-1])


def aes128(key, block):
    result = aes.aes_enc_core(words(block), _aes_schedule(key))
    return b"".join(x.to_bytes(4, "big") for x in result)


def _gf8_table(powers):
    return [sum(snow.MULxPOW(x, n, 0xa9) << (24 - 8 * i)
                for i, n in enumerate(powers)) for x in range(256)]


# Replace the reference's very slow debug/iterative implementation with
# equivalent precomputed tables. The RTL instead uses constant XOR matrices.
_mulalpha = _gf8_table((23, 245, 48, 239))
_divalpha = _gf8_table((16, 39, 6, 64))
snow.MULalpha = _mulalpha.__getitem__
snow.DIValpha = _divalpha.__getitem__


def keystream(alg, key, iv, nwords):
    s = [0] * 16
    r = [0] * (3 if alg == 1 else 2)
    primitive = snow if alg == 1 else zuc
    primitive.init_parameters(words(key)[::-1], words(iv)[::-1], s, r)
    core = snow.snow_3g_core if alg == 1 else zuc.zuc_core
    for i in range(33):  # 32 initialization clocks, one discarded clock
        _, _, s, r = core(int(i < 32), 0, s, r)
    out = []
    for _ in range(nwords):
        z, _, s, r = core(0, 0, s, r)
        out.append(z)
    return out


def cipher(alg, key, count, bearer, direction, msg):
    if alg == 0:
        return msg
    prefix = count.to_bytes(4, "big") + bytes([(bearer << 3) | (direction << 2), 0, 0, 0])
    if alg == 2:
        stream = b"".join(aes128(key, prefix + i.to_bytes(8, "big"))
                          for i in range((len(msg) + 15) // 16))
    else:
        stream = b"".join(x.to_bytes(4, "big") for x in keystream(
            alg, key, prefix + prefix, (len(msg) + 3) // 4))
    return bytes(x ^ y for x, y in zip(msg, stream))


def gf64(x, y):
    result = 0
    for _ in range(64):
        if y & 1:
            result ^= x
        x = ((x << 1) & MASK64) ^ (0x1b if x >> 63 else 0)
        y >>= 1
    return result


def _double(x):
    return ((x << 1) & MASK128) ^ (0x87 if x >> 127 else 0)


def integrity(alg, key, count, bearer, direction, msg):
    if alg == 0:
        return 0
    if alg == 2:
        prefix = count.to_bytes(4, "big") + bytes([(bearer << 3) | (direction << 2), 0, 0, 0])
        message = prefix + msg
        k1 = _double(int.from_bytes(aes128(key, bytes(16)), "big"))
        k2 = _double(k1)
        if len(message) % 16:
            message += b"\x80" + bytes(15 - len(message) % 16)
            subkey = k2
        else:
            subkey = k1
        state = 0
        for offset in range(0, len(message), 16):
            block = int.from_bytes(message[offset:offset + 16], "big")
            if offset + 16 == len(message):
                block ^= subkey
            state = int.from_bytes(aes128(key, (state ^ block).to_bytes(16, "big")), "big")
        return state >> 96

    fresh = bearer << 27
    iv = (count.to_bytes(4, "big") + fresh.to_bytes(4, "big") +
          (count ^ (direction << 31)).to_bytes(4, "big") +
          (fresh ^ (direction << 15)).to_bytes(4, "big"))
    if alg == 1:
        z = keystream(1, key, iv, 5)
        p, q = z[0] << 32 | z[1], z[2] << 32 | z[3]
        acc = 0
        for offset in range(0, len(msg), 8):
            chunk = msg[offset:offset + 8].ljust(8, b"\0")
            acc = gf64(acc ^ int.from_bytes(chunk, "big"), p)
        return ((gf64(acc ^ (len(msg) * 8), q) >> 32) ^ z[4]) & MASK32

    z = keystream(3, key, iv, (len(msg) + 3) // 4 + 2)

    def window(bit_index):
        w, shift = divmod(bit_index, 32)
        if not shift:
            return z[w]
        return ((z[w] << shift) | (z[w + 1] >> (32 - shift))) & MASK32

    acc = 0
    for i in range(len(msg) * 8):
        if msg[i // 8] & (0x80 >> (i % 8)):
            acc ^= window(i)
    return acc ^ window(len(msg) * 8) ^ z[(len(msg) + 3) // 4 + 1]


def packet(mode, enc_alg, int_alg, enc_key, int_key, count, bearer, direction, a, b):
    """Return calculated MAC/valid, output bytes, received MAC/valid, match."""
    enc = lambda data: cipher(enc_alg, enc_key, count, bearer, direction, data)
    mac = lambda data: integrity(int_alg, int_key, count, bearer, direction, data)
    if mode == 0:
        return 0, False, enc(b), 0, False, False
    if mode == 1:
        return mac(a + b), True, b, 0, False, False
    if mode == 2:
        value = mac(a + b)
        return value, True, enc(b + value.to_bytes(4, "big")), 0, False, False
    if mode == 3:
        result = enc(b)
        return mac(a + result), True, result, 0, False, False
    if mode == 4:
        return mac(a + b), True, enc(b), 0, False, False
    if mode == 5:
        if len(b) < 4:
            raise ValueError("mode 5 requires at least four encrypted MAC bytes")
        decrypted = enc(b)
        received = int.from_bytes(decrypted[-4:], "big")
        value = mac(a + decrypted[:-4])
        return value, True, decrypted[:-4], received, True, received == value
    raise ValueError(mode)
