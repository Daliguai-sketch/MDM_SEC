#!/usr/bin/env python3
"""Create deterministic packet-level known-answer and differential vectors."""
import random
import sys
from pathlib import Path

# This repository already tracks some historical .pyc files. Do not modify
# them merely by running a regression.
sys.dont_write_bytecode = True
from reference_model import aes128, cipher, integrity, packet

RNG = random.Random(0x3A_33_401)
OUT = Path(sys.argv[1] if len(sys.argv) > 1 else "build/packet_vectors.txt")
OUT.parent.mkdir(parents=True, exist_ok=True)
cases = []


def add(mode, ca, ia, ck, ik, count, bearer, direction, a, b, *, fixed_mac=None,
        fixed_cipher=None, fixed_rx=None, fixed_match=None):
    mac, mac_valid, ciphertext, rx, rx_valid, match = packet(
        mode, ca, ia, ck, ik, count, bearer, direction, a, b)
    if fixed_mac is not None:
        assert mac == fixed_mac, (hex(mac), hex(fixed_mac))
        mac = fixed_mac
    if fixed_cipher is not None:
        assert ciphertext == fixed_cipher, (ciphertext.hex(), fixed_cipher.hex())
        ciphertext = fixed_cipher
    if fixed_rx is not None:
        assert rx == fixed_rx, (hex(rx), hex(fixed_rx))
    if fixed_match is not None:
        assert match == fixed_match
    assert len(a) + len(b) <= 2048
    cases.append((mode, ca, ia, ck, ik, count, bearer, direction, a, b,
                  mac, mac_valid, ciphertext, rx, rx_valid, match))


def hx(s):
    return bytes.fromhex(s)


# FIPS 197 AES primitive example, checked against the Python primitive too.
assert aes128(hx("000102030405060708090a0b0c0d0e0f"),
              hx("00112233445566778899aabbccddeeff")) == hx("69c4e0d86a7b0430d8cdb78070b4c55a")

# TS 33.401 Annex C EEA1/EEA2 set 1, byte-aligned 256-bit extension.
key = hx("d3c5d592327fb11c4035c6680af8c6d1")
msg = hx("981ba6824c1bfb1ab485472029b71d808ce33e2cc3c0b5fc1f3de8a6dc66b1f0")
add(0, 1, 0, key, bytes(16), 0x398a59b4, 0x15, 1, b"", msg,
    fixed_cipher=hx("5d5bfe75eb04f68ce0a12377ea00b37d47c6a0ba06309155086a859c4341b37c"))
add(0, 2, 0, key, bytes(16), 0x398a59b4, 0x15, 1, b"", msg,
    fixed_cipher=hx("e9fed8a63d155304d71df20bf3e82214b20ed7dad2f233dc3c22d7bdeeed8e78"))

# 128-EEA3 implementor test set 2, complete 800-bit vector.
key3 = hx("e5bd3ea0eb55ade866c6ac58bd54302a")
msg3 = hx("14a8ef693d678507bbe7270a7f67ff5006c3525b9807e467c4e56000ba338f5d"
          "429559036751822246c80d3b38f07f4be2d8ff5805f5132229bde93bbbdcaf38"
          "2bf1ee972fbf9977bada8945847a2a6c9ad34a667554e04d1f7fa2c33241bd8f01ba220d")
ct3 = hx("131d43e0dea1be5c5a1bfd971d852cbf712d7b4f57961fea3208afa8bca433f4"
         "56ad09c7417e58bc69cf8866d1353f74865e80781d202dfb3ecff7fcbc3b190f"
         "e82a204ed0e350fc0f6f2613b2f2bca6df5a473a57a4a00d985ebad880d6f23864a07b01")
add(0, 3, 0, key3, bytes(16), 0x56823, 0x18, 1, b"", msg3, fixed_cipher=ct3)

# EIA1 TS 33.401 Annex C.4 set 1, deliberately split at an unaligned a/b boundary.
iki = hx("2bd6459f82c5b300952c49104881ff48")
mi = hx("3332346263393861373479")
add(1, 0, 1, bytes(16), iki, 0x38a6f056, 0x1f, 0, mi[:3], mi[3:], fixed_mac=0x731f1165)
# EIA1 set 4, 768 bits, direction=1 and multiple GF(2^64) blocks.
iki4 = hx("83fd23a244a74cf358da3019f1722635")
mi4 = hx("35c68716633c66fb750c266865d53c11ea05b1e9fa49c8398d48e1efa5909d39"
         "47902837f5ae96d5a05bc8d61ca8dbef1b13a4b4abfe4fb1006045b674bb5472"
         "9304c382be53a5af05556176f6eaa2ef1d05e4b083181ee674cda5a485f74d7a")
add(1, 0, 1, bytes(16), iki4, 0x36af6144, 0x0f, 1, mi4[:13], mi4[13:], fixed_mac=0xbba74492)
# EIA2 byte-aligned 64-bit test (Open5GS security-test 6).
mi2 = hx("484583d5afe082ae")
add(1, 0, 2, bytes(16), key, 0x398a59b4, 0x1a, 1, mi2[:1], mi2[1:], fixed_mac=0xb93787e6)
# EIA3 byte-aligned 584-bit extension of TS 35.223 set 3 (Open5GS test 8).
keyi3_long = hx("c9e6cec4607c72db000aefa88385ab0a")
mi3_long = hx("983b41d47d780c9e1ad11d7eb70391b1de0b35da2dc62f83e7b78d6306ca0ea0"
              "7e941b7be91348f9fcb170e2217fecd97f9f68adb16e5d7d21e569d280ed775c"
              "ebde3f4093c5388100")
add(1, 0, 3, bytes(16), keyi3_long, 0xa94059da, 0x0a, 1,
    mi3_long[:19], mi3_long[19:], fixed_mac=0x24a842b3)
# EIA3 byte-aligned independent cross-check against srsRAN's ZUC primitive
# and the TS 35.223 EIA3 equations; direction=1 exercises both IV bits.
keyi3 = hx("47054125561eb2dda94059da05097850")
mi3 = hx("99022dc44019213ac8ef51")
add(1, 0, 3, bytes(16), keyi3, 0x561eb2dd, 0x14, 1, mi3[:5], mi3[5:], fixed_mac=0xb1811961)
# EIA2 independent AES-CMAC result (PyCryptodome), prefix plus 9 message bytes.
add(1, 0, 2, bytes(16), key, 0x982facb5, 0x16, 1,
    bytes(range(3)), bytes(range(3, 9)), fixed_mac=0x6bd02001)

# Cross every mode with every pair of cipher/integrity algorithms, including
# EEA0/EIA0. Lengths deliberately hit empty, partial-word, CMAC/GF boundaries.
lengths = [(0,0),(0,1),(1,0),(1,1),(3,5),(7,9),(8,8),(15,17),
           (16,16),(17,31),(31,32),(64,64),(3,125)]
for mode in range(5):
    for ca in range(4):
        for ia in range(4):
            al,bl=lengths[(mode*19+ca*7+ia*3) % len(lengths)]
            randbytes=lambda n: bytes(RNG.randrange(256) for _ in range(n))
            add(mode,ca,ia,randbytes(16),randbytes(16),RNG.getrandbits(32),
                RNG.randrange(32),RNG.randrange(2),randbytes(al),randbytes(bl))

# Boundary sweep for same/different algorithms and all five scheduling modes.
for mode in range(5):
    for alg in (1,2,3):
        for n in (0,1,2,3,4,7,8,9,15,16,17,24,31,32,33,63):
            al=n % 5
            bl=n
            randbytes=lambda k: bytes(RNG.randrange(256) for _ in range(k))
            add(mode, alg, 1+(alg % 3), randbytes(16),randbytes(16),
                RNG.getrandbits(32), RNG.randrange(32), RNG.randrange(2), randbytes(al),randbytes(bl))

# Exercise the default 2048-byte capacity and high SRAM bank addresses.
# Include simultaneous processing, MAC appending and the enc->int readback.
for mode,al,bl in ((4,777,1271),(2,1023,1025),(3,1,2047)):
    for alg in (1,2,3):
        randbytes=lambda n: bytes(RNG.randrange(256) for _ in range(n))
        add(mode,alg,1+(alg % 3),randbytes(16),randbytes(16),
            RNG.getrandbits(32),RNG.randrange(32),RNG.randrange(2),randbytes(al),randbytes(bl))

# Long enough for real lane transfers to overlap for every EEA/EIA pairing
# with a non-null integrity algorithm, including the EEA0 bypass. The mode-2
# B/MAC and mode-3 A/B splits deliberately cross 32-bit word boundaries.
for mode,al,bl in ((2,321,703),(3,1,1023),(4,397,627)):
    for ca in range(4):
        for ia in (1,2,3):
            randbytes=lambda n: bytes(RNG.randrange(256) for _ in range(n))
            add(mode,ca,ia,randbytes(16),randbytes(16),
                RNG.getrandbits(32),RNG.randrange(32),RNG.randrange(2),randbytes(al),randbytes(bl))

# Sweep every 128-bit A/B byte alignment in every mode. Both segments
# contain at least one complete beat, so the transition and partial beats
# also exercise unaligned 16-bank writes and MAC insertion.
for mode in range(5):
    for a_tail in range(16):
        for b_tail in range(16):
            randbytes=lambda n: bytes(RNG.randrange(256) for _ in range(n))
            add(mode,(a_tail+mode)%4,(b_tail+mode)%4,randbytes(16),randbytes(16),
                RNG.getrandbits(32),RNG.randrange(32),RNG.randrange(2),
                randbytes(16+a_tail),randbytes(16+b_tail))

# Mode 5 is the receive-side inverse of mode 2: decrypt B=enc(payload||MAC),
# remove the final four bytes, and calculate int(A||payload). Exercise both a
# valid tag and a one-bit tag corruption for every cipher/integrity pairing.
def add_mode5_pair(ca, ia, alen, payload_len, *, include_bad=True, bad_byte=3, include_encrypt=False):
    randbytes = lambda n: bytes(RNG.randrange(256) for _ in range(n))
    ck, ik = randbytes(16), randbytes(16)
    count, bearer, direction = RNG.getrandbits(32), RNG.randrange(32), RNG.randrange(2)
    a, payload = randbytes(alen), randbytes(payload_len)
    value = integrity(ia, ik, count, bearer, direction, a + payload)
    encrypted = cipher(ca, ck, count, bearer, direction, payload + value.to_bytes(4, "big"))
    assert packet(2, ca, ia, ck, ik, count, bearer, direction, a, payload)[2] == encrypted
    if include_encrypt:
        add(2, ca, ia, ck, ik, count, bearer, direction, a, payload,
            fixed_mac=value, fixed_cipher=encrypted)
    add(5, ca, ia, ck, ik, count, bearer, direction, a, encrypted,
        fixed_mac=value, fixed_cipher=payload, fixed_rx=value, fixed_match=True)
    if include_bad:
        damaged = bytearray(encrypted)
        damaged[-4+bad_byte] ^= 1
        changed_bit = 1 << (8*(3-bad_byte))
        add(5, ca, ia, ck, ik, count, bearer, direction, a, bytes(damaged),
            fixed_mac=value, fixed_cipher=payload, fixed_rx=value ^ changed_bit, fixed_match=False)


for ca in range(4):
    for ia in range(4):
        for payload_len in (0, 1, 2, 3, 4, 7, 8, 9, 12, 13, 14, 15, 16, 17, 31, 32, 33):
            add_mode5_pair(ca, ia, (payload_len * 7 + ca + ia) % 17, payload_len,
                           include_encrypt=(payload_len==17))
        # Flip each of the other three received-MAC bytes separately.
        for bad_byte in range(3):
            add_mode5_pair(ca, ia, 13+bad_byte, 13+bad_byte, bad_byte=bad_byte)

# Empty A and empty payload still require decrypting and checking four bytes.
for ca in range(4):
    for ia in range(4):
        add_mode5_pair(ca, ia, 0, 0)

# Cover every A alignment and every decrypted-tag start position modulo 16.
for a_tail in range(16):
    for payload_tail in range(16):
        add_mode5_pair((a_tail+2)%4, (payload_tail+1)%4,
                       16+a_tail, 16+payload_tail, include_bad=False)

# Alter a payload byte or an A byte while keeping the received tag unchanged.
# EIA0 is excluded here because its constant MAC provides no authentication.
for ca in range(4):
    for ia in (1, 2, 3):
        randbytes = lambda n: bytes(RNG.randrange(256) for _ in range(n))
        ck, ik = randbytes(16), randbytes(16)
        count, bearer, direction = RNG.getrandbits(32), RNG.randrange(32), RNG.randrange(2)
        a, payload = randbytes(13), randbytes(19)
        value = integrity(ia, ik, count, bearer, direction, a+payload)
        encrypted = cipher(ca, ck, count, bearer, direction, payload+value.to_bytes(4, "big"))
        changed_payload = bytes([payload[0] ^ 1])+payload[1:]
        changed_cipher = bytes([encrypted[0] ^ 1])+encrypted[1:]
        assert integrity(ia, ik, count, bearer, direction, a+changed_payload) != value
        add(5, ca, ia, ck, ik, count, bearer, direction, a, changed_cipher,
            fixed_cipher=changed_payload, fixed_rx=value, fixed_match=False)
        changed_a = bytes([a[0] ^ 1])+a[1:]
        assert integrity(ia, ik, count, bearer, direction, changed_a+payload) != value
        add(5, ca, ia, ck, ik, count, bearer, direction, changed_a, encrypted,
            fixed_cipher=payload, fixed_rx=value, fixed_match=False)

# Mode 5 includes the four tag bytes in the input-buffer capacity.
for alg in (1, 2, 3):
    alen = 1 + 13*alg
    add_mode5_pair(alg, 1+(alg % 3), alen, 2048-alen-4)

# Cover simultaneous decrypt/authentication transfers for all EEA algorithms
# paired with each non-null EIA algorithm, including an unaligned A boundary.
for ca in range(4):
    for ia in (1, 2, 3):
        add_mode5_pair(ca, ia, 3, 1017, include_bad=False)

# A legacy parallel command after mode 5 must clear the received-tag outputs.
add(4, 2, 2, bytes(range(16)), bytes(reversed(range(16))), 0x12345678,
    3, 1, b"abc", b"payload after mode five")

# Optional independent implementation comparison. No extra dependency is
# required for the RTL regression, but installing pycryptodome adds this check.
try:
    from Crypto.Cipher import AES
    from Crypto.Hash import CMAC
except ImportError:
    print("PyCryptodome not installed: fixed KATs still run; independent AES cross-check skipped")
else:
    for _,_,_,ck,ik,count,bearer,direction,a,b,_,_,_,_,_,_ in cases[6:36]:
        prefix=count.to_bytes(4,"big")+bytes([(bearer<<3)|(direction<<2),0,0,0])
        c=CMAC.new(ik,ciphermod=AES)
        c.update(prefix+a+b)
        assert integrity(2,ik,count,bearer,direction,a+b)==int.from_bytes(c.digest()[:4],"big")
        ctr=AES.new(ck,AES.MODE_CTR,nonce=prefix,initial_value=0)
        assert cipher(2,ck,count,bearer,direction,b)==ctr.encrypt(b)
    for mode,ca,ia,ck,ik,count,bearer,direction,a,b,mac,_,out,rx,_,match in cases:
        if mode != 5 or ca != 2 or ia != 2:
            continue
        prefix=count.to_bytes(4,"big")+bytes([(bearer<<3)|(direction<<2),0,0,0])
        decrypted=AES.new(ck,AES.MODE_CTR,nonce=prefix,initial_value=0).decrypt(b)
        c=CMAC.new(ik,ciphermod=AES)
        c.update(prefix+a+decrypted[:-4])
        independent=int.from_bytes(c.digest()[:4],"big")
        assert decrypted[:-4]==out and int.from_bytes(decrypted[-4:],"big")==rx
        assert independent==mac and (independent==rx)==match
    print("PASS independent PyCryptodome EEA2/EIA2 and mode 5 cross-check")


def beat_words(buf):
    for i in range(0,len(buf),16):
        yield int.from_bytes(buf[i:i+16].ljust(16,b"\0"),"big")


with OUT.open("w") as f:
    for idx,(mode,ca,ia,ck,ik,count,bearer,direction,a,b,mac,mv,ct,rx,rv,match) in enumerate(cases):
        f.write(f"{idx} {mode} {ca} {ia} {ck.hex()} {ik.hex()} {count:08x} "
                f"{bearer} {direction} {len(a)} {len(b)} {mac:08x} {int(mv)} {len(ct)} "
                f"{rx:08x} {int(rv)} {int(match)}\n")
        for word in (*beat_words(a),*beat_words(b),*beat_words(ct)):
            f.write(f"{word:032x}\n")
print(f"Generated {len(cases)} deterministic packet cases: {OUT}")
