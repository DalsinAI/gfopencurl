#!/bin/sh
# Kitchen stove entry for gfopencurl. The compiler is the one already on
# the stove. The tarballs, the gfopentls headers and the zlib link check
# are the same ones tests/amiga/ci-build.sh uses. libcurl.a is the result.
# A program's own gzip stays on gzip.datatype. This zlib is only so curl
# can ask for a compressed HTTP body.
# Copyright (c) 2026 AmiCradle Team. MIT.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
OUT=${OUT:-"$HERE/out"}
WORK="$HERE/work/kitchen"
mkdir -p "$WORK" "$OUT"

if [ -z "${OS32_GCC16:-}" ] || [ ! -x "${OS32_GCC16}/prefix/bin/m68k-amigaos-gcc" ]; then
  CC=$(command -v m68k-amigaos-gcc || true)
  [ -n "$CC" ] || { echo "no m68k-amigaos-gcc on this stove"; exit 2; }
  PRE=$(CDPATH= cd -- "$(dirname -- "$CC")/.." && pwd)
  mkdir -p "$WORK/stove"
  ln -sfn "$PRE" "$WORK/stove/prefix"
  OS32_GCC16="$WORK/stove"
fi

TARBALLS=${TARBALLS:-"$HERE/tarballs"}
mkdir -p "$TARBALLS"
fetch() {
  dest=$1
  url=$2
  sum=$3
  if [ ! -f "$dest" ] || ! echo "$sum  $dest" | sha256sum -c - >/dev/null 2>&1; then
    echo "fetch $(basename "$dest")"
    curl -fsSL --retry 3 -o "$dest.part" "$url"
    mv "$dest.part" "$dest"
  fi
  echo "$sum  $dest" | sha256sum -c - >/dev/null || { echo "SHA-256 mismatch: $dest"; exit 2; }
}
fetch "$TARBALLS/curl-8.22.0.tar.xz" \
  https://curl.se/download/curl-8.22.0.tar.xz \
  f7ef3ae8a22e521f289803fe93543eb64c329b58aa73a9e224dfd915a2a5f4f7
fetch "$TARBALLS/nghttp2-1.70.0.tar.xz" \
  https://github.com/nghttp2/nghttp2/releases/download/v1.70.0/nghttp2-1.70.0.tar.xz \
  e05cb1388eaca3830aded4ccf20044b6e1ac1a61411dcca11b0437c4285c8bc2
fetch "$TARBALLS/zlib-1.3.1.tar.xz" \
  https://github.com/madler/zlib/releases/download/v1.3.1/zlib-1.3.1.tar.xz \
  38ef96b8dfe510d42707d9c781877914792541133e1870841463bfa73f883e32

if [ -z "${OPENTLS_INCLUDE:-}" ] || [ ! -f "${OPENTLS_INCLUDE}/proto/gfopentls.h" ]; then
  OPENTLS_INCLUDE=
  for c in \
    "$HERE/../gfopentls/include" \
    /srv/samsung/kitchen/builds/DalsinAI__gfopentls/include
  do
    if [ -f "$c/proto/gfopentls.h" ]; then
      OPENTLS_INCLUDE=$c
      break
    fi
  done
fi
if [ -z "${OPENTLS_INCLUDE:-}" ]; then
  OT="$WORK/gfopentls"
  if [ ! -f "$OT/include/proto/gfopentls.h" ]; then
    rm -rf "$OT"
    mkdir -p "$OT"
    if ! git -C "$OT" init -q \
      || ! git -C "$OT" fetch -q --depth 1 https://github.com/DalsinAI/gfopentls.git bc509d410e306369fa39cb91fe94c3d25cf8b228 \
      || ! git -C "$OT" checkout -q FETCH_HEAD; then
      rm -rf "$OT"
      git clone --depth 1 https://github.com/DalsinAI/gfopentls.git "$OT"
    fi
  fi
  OPENTLS_INCLUDE="$OT/include"
fi
[ -f "$OPENTLS_INCLUDE/proto/gfopentls.h" ] || { echo "no gfopentls headers"; exit 2; }

DEPS="$WORK/deps"
if [ ! -f "$DEPS/lib/libz.a" ]; then
  rm -rf "$WORK/zlib-src" "$WORK/zobj"
  mkdir -p "$WORK/zlib-src" "$WORK/zobj" "$DEPS/lib" "$DEPS/include"
  tar xf "$TARBALLS/zlib-1.3.1.tar.xz" -C "$WORK/zlib-src"
  ZSRC=$(echo "$WORK/zlib-src"/zlib-*)
  CC="$OS32_GCC16/prefix/bin/m68k-amigaos-gcc"
  AR="$OS32_GCC16/prefix/bin/m68k-amigaos-ar"
  CPU="-m68040 -m68881 -mcrt=nix20"
  for f in adler32 crc32 deflate infback inffast inflate inftrees trees zutil compress uncompr gzclose gzlib gzread gzwrite; do
    $CC -O2 $CPU -DHAVE_UNISTD_H -c "$ZSRC/$f.c" -o "$WORK/zobj/$f.o"
  done
  $AR rcs "$DEPS/lib/libz.a" "$WORK/zobj"/*.o
  cp "$ZSRC/zlib.h" "$ZSRC/zconf.h" "$DEPS/include/"
fi

export OS32_GCC16 OPENTLS_INCLUDE TARBALLS JOBS="${JOBS:-2}"
export DEPS_PREFIX="$DEPS"
export PREFIX="$OUT"
sh "$HERE/build.sh" || {
  [ -f "$OUT/lib/libcurl.a" ] || exit 1
  echo "libcurl.a is built; the curltest link did not finish"
}
mkdir -p "$OUT/lib" "$OUT/include"
cp "$DEPS/lib/libz.a" "$OUT/lib/libz.a"
cp "$DEPS/include/zlib.h" "$DEPS/include/zconf.h" "$OUT/include/"
echo "kitchen curl: $OUT/lib/libcurl.a"
