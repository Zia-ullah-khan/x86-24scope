import struct
from pathlib import Path

d = Path("firmware/IWLWIFI.UC").read_bytes()
HDR = 88  # sizeof(iwl_tlv_ucode_header) before data[]
STORE = {1, 2, 3, 4, 11, 14, 15, 0x100, 0x101}

off = HDR
n = len(d)
types = {}
secs = []
while off + 8 <= n:
    typ, length = struct.unpack_from("<II", d, off)
    off += 8
    aligned = (length + 3) & ~3
    if off + aligned > n:
        print("TRUNC", hex(typ), length, "at", off - 8)
        break
    types[typ] = types.get(typ, 0) + 1
    if typ in STORE or typ >= 0x100:
        secs.append((hex(typ), length))
    off += aligned
else:
    print("parse OK remaining", n - off)

print("header human:", d[8:72].split(b"\x00")[0])
print("ver", hex(struct.unpack_from("<I", d, 72)[0]), "build", hex(struct.unpack_from("<I", d, 76)[0]))
print("interesting", len(secs))
for s in secs[:50]:
    print(" ", s)
print("all types", dict(sorted(types.items())))

off = HDR
cnt = 0
while off + 8 <= n:
    typ, length = struct.unpack_from("<II", d, off)
    off += 8
    aligned = (length + 3) & ~3
    if off + aligned > n:
        break
    if typ in STORE:
        cnt += 1
    off += aligned
print("asm store count with current filter", cnt)

# Also check newer section types from file.h
# IWL_UCODE_TLV_SECURE_SEC_RT = 0x100 etc already in STORE
# Maybe MEM_DESC only?
print("sec-like types present:", {hex(t): c for t, c in types.items() if t in STORE or t in (0x300, 18, 19, 22, 23)})
