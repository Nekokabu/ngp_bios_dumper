#!/usr/bin/env python3
"""Cut the BIOS dumps out of a cartridge backup made with Flash Masta.

    python3 extract.py cart_backup.ngp

Writes ngp_bios.bin  (from offset 0x010000, dumped on a mono NGP)
       ngpc_bios.bin (from offset 0x040000, dumped on an NGPC)
for each area that is not blank, and prints CRC32 / SHA-1 of each.
"""
import hashlib
import sys
import zlib

AREAS = [("ngp_bios.bin", 0x010000, "Neo Geo Pocket (mono)"),
         ("ngpc_bios.bin", 0x040000, "Neo Geo Pocket Color")]
SIZE = 0x10000


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    data = open(sys.argv[1], "rb").read()
    found = 0
    for name, off, label in AREAS:
        chunk = data[off:off + SIZE]
        if len(chunk) < SIZE:
            print(f"{label}: backup too short (need at least {off + SIZE:#x} bytes)")
            continue
        if chunk == b"\xff" * SIZE:
            print(f"{label}: empty (not dumped on this console yet)")
            continue
        with open(name, "wb") as f:
            f.write(chunk)
        found += 1
        print(f"{label}: wrote {name}")
        print(f"    CRC32 {zlib.crc32(chunk):08X}   (compare with the CRC shown on screen)")
        print(f"    SHA1  {hashlib.sha1(chunk).hexdigest()}")
    if not found:
        sys.exit("no dump found in this backup")


if __name__ == "__main__":
    main()
