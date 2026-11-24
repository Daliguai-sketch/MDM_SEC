#!/usr/bin/env python3
"""Small deterministic, self-checking packet suite for waveform inspection."""
import sys
from pathlib import Path

sys.dont_write_bytecode = True
from reference_model import cipher, integrity, packet

OUT = Path(sys.argv[1] if len(sys.argv) > 1 else "build/rtl/wave_vectors.txt")
OUT.parent.mkdir(parents=True, exist_ok=True)
CK = bytes(range(16))
IK = bytes(reversed(range(16)))
COUNT = 0x398A59B4
BEARER = 0x15
DIRECTION = 1
cases = []


def hx(value):
    return bytes.fromhex(value)


def add(name, mode, ca, ia, a, b, *, ck=CK, ik=IK, count=COUNT,
        bearer=BEARER, direction=DIRECTION, fixed_mac=None, fixed_out=None,
        fixed_rx=None, fixed_match=None):
    assert len(a) + len(b) <= 512
    mac, valid, out, rx, rx_valid, match = packet(
        mode, ca, ia, ck, ik, count, bearer, direction, a, b)
    if fixed_mac is not None:
        assert mac == fixed_mac, name
    if fixed_out is not None:
        assert out == fixed_out, name
    if fixed_rx is not None:
        assert rx == fixed_rx, name
    if fixed_match is not None:
        assert match == fixed_match, name
    cases.append((name, mode, ca, ia, ck, ik, count, bearer, direction,
                  a, b, mac, valid, out, rx, rx_valid, match))


# Published 3GPP confidentiality vectors (byte-aligned cases).
key12 = hx("d3c5d592327fb11c4035c6680af8c6d1")
msg12 = hx("981ba6824c1bfb1ab485472029b71d808ce33e2cc3c0b5fc1f3de8a6dc66b1f0")
add("EEA1 known answer", 0, 1, 0, b"", msg12, ck=key12,
    fixed_out=hx("5d5bfe75eb04f68ce0a12377ea00b37d47c6a0ba06309155086a859c4341b37c"))
add("EEA2 known answer", 0, 2, 0, b"", msg12, ck=key12,
    fixed_out=hx("e9fed8a63d155304d71df20bf3e82214b20ed7dad2f233dc3c22d7bdeeed8e78"))
key3 = hx("e5bd3ea0eb55ade866c6ac58bd54302a")
msg3 = hx("14a8ef693d678507bbe7270a7f67ff5006c3525b9807e467c4e56000ba338f5d"
          "429559036751822246c80d3b38f07f4be2d8ff5805f5132229bde93bbbdcaf38"
          "2bf1ee972fbf9977bada8945847a2a6c9ad34a667554e04d1f7fa2c33241bd8f01ba220d")
ct3 = hx("131d43e0dea1be5c5a1bfd971d852cbf712d7b4f57961fea3208afa8bca433f4"
         "56ad09c7417e58bc69cf8866d1353f74865e80781d202dfb3ecff7fcbc3b190f"
         "e82a204ed0e350fc0f6f2613b2f2bca6df5a473a57a4a00d985ebad880d6f23864a07b01")
add("EEA3 known answer", 0, 3, 0, b"", msg3, ck=key3,
    count=0x56823, bearer=0x18, direction=1, fixed_out=ct3)

# Published/cross-checked integrity vectors, with unaligned A/B splits.
msg1 = hx("3332346263393861373479")
add("EIA1 known answer", 1, 0, 1, msg1[:3], msg1[3:],
    ik=hx("2bd6459f82c5b300952c49104881ff48"),
    count=0x38a6f056, bearer=0x1f, direction=0, fixed_mac=0x731f1165)
msg2 = hx("484583d5afe082ae")
add("EIA2 known answer", 1, 0, 2, msg2[:1], msg2[1:],
    ik=key12, bearer=0x1a, fixed_mac=0xb93787e6)
msg_i3 = hx("99022dc44019213ac8ef51")
add("EIA3 known answer", 1, 0, 3, msg_i3[:5], msg_i3[5:],
    ik=hx("47054125561eb2dda94059da05097850"),
    count=0x561eb2dd, bearer=0x14, direction=1, fixed_mac=0xb1811961)

# Mode 2→5 round trip, including an intentionally corrupted MAC byte.
a = hx("1122334455")
payload = bytes(range(0x30, 0x43))
mac = integrity(2, IK, COUNT, BEARER, DIRECTION, a + payload)
encrypted = cipher(2, CK, COUNT, BEARER, DIRECTION, payload + mac.to_bytes(4, "big"))
add("mode 2 AES append MAC", 2, 2, 2, a, payload, fixed_mac=mac, fixed_out=encrypted)
add("mode 2 original-data hazard", 2, 0, 2, bytes(range(7)), bytes(range(37)))
# The long B makes even the 5-cycle AES producer eventually lag EIA3,
# so ciphertext-dependency waits are observable in both AES configurations.
add("mode 3 ciphertext dependency", 3, 2, 3, bytes(range(3)), bytes(i & 255 for i in range(493)))
add("mode 4 original-data hazard", 4, 0, 2, bytes(range(5)), bytes(range(31)))
add("mode 4 quickstart fixed answer", 4, 2, 2, a, hx("667788"),
    fixed_mac=0xf387a200, fixed_out=hx("738300"))
add("mode 5 valid MAC", 5, 2, 2, a, encrypted,
    fixed_mac=mac, fixed_out=payload, fixed_rx=mac, fixed_match=True)
corrupt_tag = encrypted[:-1] + bytes([encrypted[-1] ^ 1])
add("mode 5 corrupted MAC", 5, 2, 2, a, corrupt_tag,
    fixed_mac=mac, fixed_out=payload, fixed_rx=mac ^ 1, fixed_match=False)

empty_mac = integrity(2, IK, COUNT, BEARER, DIRECTION, b"")
empty_cipher = cipher(2, CK, COUNT, BEARER, DIRECTION, empty_mac.to_bytes(4, "big"))
add("mode 5 tag only, empty plaintext", 5, 2, 2, b"", empty_cipher,
    fixed_mac=empty_mac, fixed_out=b"", fixed_rx=empty_mac, fixed_match=True)
add("mode 4 empty A/B with NULL algorithms", 4, 0, 0, b"", b"", fixed_mac=0, fixed_out=b"")
add("mode 2 empty B plus MAC", 2, 2, 2, b"abc", b"")
add("mode 3 ZUC plus SNOW3G", 3, 3, 1, bytes(range(14)), bytes(range(35)))
add("mode 4 SNOW3G plus ZUC", 4, 1, 3, bytes(range(15)), bytes(range(33)))
payload_i3 = bytes(i & 255 for i in range(495))
mac_i3 = integrity(3, IK, COUNT, BEARER, DIRECTION, payload_i3)
encrypted_i3 = cipher(2, CK, COUNT, BEARER, DIRECTION, payload_i3 + mac_i3.to_bytes(4, "big"))
add("mode 5 plaintext dependency", 5, 2, 3, b"", encrypted_i3,
    fixed_mac=mac_i3, fixed_out=payload_i3, fixed_rx=mac_i3, fixed_match=True)
corrupt_payload = bytes([encrypted_i3[0] ^ 1]) + encrypted_i3[1:]
add("mode 5 corrupted plaintext", 5, 2, 3, b"", corrupt_payload,
    fixed_rx=mac_i3, fixed_match=False)

# Check every AES-CTR/CMAC use with a separate implementation when available.
try:
    from Crypto.Cipher import AES
    from Crypto.Hash import CMAC
except ImportError:
    print("PyCryptodome not installed: independent AES cross-check skipped")
else:
    for name, mode, ca, ia, ck, ik, count, bearer, direction, a, b, mac, _, out, rx, _, match in cases:
        prefix = count.to_bytes(4, "big") + bytes([(bearer << 3) | (direction << 2), 0, 0, 0])
        if mode != 1 and ca == 2:
            checker = AES.new(ck, AES.MODE_CTR, nonce=prefix, initial_value=0)
            if mode == 5:
                decoded = checker.decrypt(b)
                assert decoded[:-4] == out and int.from_bytes(decoded[-4:], "big") == rx, name
            else:
                data = b + (mac.to_bytes(4, "big") if mode == 2 else b"")
                assert checker.encrypt(data) == out, name
        if mode != 0 and ia == 2:
            cmac = CMAC.new(ik, ciphermod=AES)
            cmac.update(prefix + a + (out if mode in (3, 5) else b))
            assert int.from_bytes(cmac.digest()[:4], "big") == mac, name
            if mode == 5:
                assert (rx == mac) == match, name
    print("PASS independent PyCryptodome checks for waveform AES cases")


def beat_words(buf):
    for offset in range(0, len(buf), 16):
        yield int.from_bytes(buf[offset:offset + 16].ljust(16, b"\0"), "big")


manifest = []
with OUT.open("w") as out_file:
    for idx, (name, mode, ca, ia, ck, ik, count, bearer, direction,
              a, b, mac, valid, out, rx, rx_valid, match) in enumerate(cases):
        out_file.write(f"{idx} {mode} {ca} {ia} {ck.hex()} {ik.hex()} {count:08x} "
                       f"{bearer} {direction} {len(a)} {len(b)} {mac:08x} {int(valid)} {len(out)} "
                       f"{rx:08x} {int(rx_valid)} {int(match)}\n")
        for segment in (a, b, out):
            for word in beat_words(segment):
                out_file.write(f"{word:032x}\n")
        manifest.append(f"{idx:02d} mode={mode} EEA={ca} EIA={ia} A={len(a)} B={len(b)} "
                        f"MAC={mac:08x} RX={rx:08x} match={int(match)}  {name}")
manifest_path = OUT.with_suffix(".cases.txt")
manifest_path.write_text("\n".join(manifest) + "\n")
print(f"Generated {len(cases)} waveform packet cases: {OUT}")
print(f"Case manifest: {manifest_path}")
