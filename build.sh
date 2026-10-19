#!/bin/sh
# Build biosdump.ngp with the Macro Assembler AS (asl + p2bin).
#
# Install AS once:
#   Debian/Ubuntu : sudo apt install asl          (if your release packages it)
#   openSUSE      : sudo zypper install asl
#   source        : git clone -b upstream https://github.com/Macroassembler-AS/asl-releases asl
#                   cd asl && cp Makefile.def-samples/Makefile.def-x86_64-unknown-linux Makefile.def
#                   make asl p2bin
#   Windows       : prebuilt binaries are on the AS home page
#                   (http://john.ccac.rwth-aachen.de:8000/as/)
set -e
ASL=${ASL:-asl}
P2BIN=${P2BIN:-p2bin}

"$ASL" -L -q biosdump.asm
# 512 KB (4 Mbit) image, unused space = FFh (= already erased flash)
"$P2BIN" -q -l 0xff -r '$200000-$27FFFF' biosdump.p biosdump.ngp
echo "built biosdump.ngp"
