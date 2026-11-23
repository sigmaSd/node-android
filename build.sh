#!/usr/bin/env bash
# Builds Node for Android as one self-contained executable.
#
# Node has an experimental Android build path (android-configure, which only exports the NDK's clang and
# calls ./configure); this script does the same steps itself so it can add --ninja and the patches in
# patches/<major>/ (most taken from Termux, see patches/README.md). Node's own OpenSSL, ICU (full), zlib,
# libuv, c-ares, nghttp2 and SQLite are compiled in and libc++ is linked statically: the result needs only
# Android's libc, libm, libdl and liblog.
#
# The source is checked against Node's signed SHASUMS256.txt (gpgv, release keys from nodejs/release-keys).
#
# Usage: ./build.sh <node version> <arm64|x64>        e.g. ./build.sh 24.22.3 arm64
#   NDK      Android NDK r29 (default: $ANDROID_HOME/ndk/<version>, then ~/.cache/node-android/ndk/<version>)
#   WORK     build folder (default: ./work); the source tree there is reused between runs of the same version
#   JOBS     parallel compile jobs (default: nproc); each V8 file can take ~1 GB of memory
# Output: out/node-v<version>-android-<arch>.tar.xz (node, LICENSE, BUILD-INFO) and its .sha256

set -euo pipefail

NDK_VERSION=29.0.14206865
# Android 9: getrandom, posix_spawn and aligned_alloc are in its libc
ANDROID_API=28

VERSION=${1:?usage: build.sh <node version> <arm64|x64>}
VERSION=${VERSION#v}
ARCH=${2:?usage: build.sh <node version> <arm64|x64>}
case "$ARCH" in
  arm64) DEST_CPU=arm64 TRIPLE=aarch64-linux-android ;;
  x64) DEST_CPU=x64 TRIPLE=x86_64-linux-android ;;
  *) echo "unknown arch '$ARCH' (arm64 or x64)" >&2; exit 1 ;;
esac

ROOT=$(cd "$(dirname "$0")" && pwd)
WORK=${WORK:-$ROOT/work}
OUT=$ROOT/out
JOBS=${JOBS:-$(nproc)}
MAJOR=${VERSION%%.*}
PATCHES=$ROOT/patches/$MAJOR
[ -d "$PATCHES" ] || { echo "Node $MAJOR is not supported yet: no patches/$MAJOR/" >&2; exit 1; }

if [ -z "${NDK:-}" ]; then
  for candidate in "${ANDROID_HOME:-/nonexistent}/ndk/$NDK_VERSION" "$HOME/.cache/node-android/ndk/$NDK_VERSION" "$HOME/.cache/nodeapk/android-sdk/ndk/$NDK_VERSION"; do
    if [ -d "$candidate" ]; then NDK=$candidate; break; fi
  done
fi
if [ -z "${NDK:-}" ] || [ ! -d "$NDK/toolchains/llvm/prebuilt/linux-x86_64" ]; then
  echo "NDK $NDK_VERSION not found; install it with: sdkmanager \"ndk;$NDK_VERSION\" (or set NDK=)" >&2
  exit 1
fi
TOOLCHAIN=$NDK/toolchains/llvm/prebuilt/linux-x86_64

# Node's configure accepts Python 3.9 to 3.14
PYTHON=
for p in python3.14 python3.13 python3.12 python3.11 python3.10; do
  if command -v $p >/dev/null; then PYTHON=$p; break; fi
done
[ -n "$PYTHON" ] || { echo "Python 3.10 to 3.14 is needed by Node's configure" >&2; exit 1; }

# The source, checked against the release's signed checksums
mkdir -p "$WORK" "$OUT"
DIST=https://nodejs.org/dist/v$VERSION
TARBALL=node-v$VERSION.tar.xz
fetch() { [ -f "$WORK/$1" ] || { curl -fsSL -o "$WORK/$1.part" "$2" && mv "$WORK/$1.part" "$WORK/$1"; }; }
fetch "$TARBALL" "$DIST/$TARBALL"
curl -fsSL -o "$WORK/SHASUMS256-$VERSION.txt" "$DIST/SHASUMS256.txt"
curl -fsSL -o "$WORK/SHASUMS256-$VERSION.txt.sig" "$DIST/SHASUMS256.txt.sig"
curl -fsSL -o "$WORK/node-release-keys.kbx" https://github.com/nodejs/release-keys/raw/HEAD/gpg-only-active-keys/pubring.kbx
gpgv --keyring "$WORK/node-release-keys.kbx" "$WORK/SHASUMS256-$VERSION.txt.sig" "$WORK/SHASUMS256-$VERSION.txt"
(cd "$WORK" && grep " $TARBALL\$" "SHASUMS256-$VERSION.txt" | sha256sum -c --quiet)

# One tree per version and architecture: out/ holds the configured build
SRC=$WORK/node-v$VERSION-$ARCH
if [ ! -f "$SRC/.patched" ]; then
  rm -rf "$SRC"
  mkdir -p "$SRC"
  tar -xf "$WORK/$TARBALL" -C "$SRC" --strip-components=1
  for patch in "$PATCHES"/*.patch; do
    echo "applying $MAJOR/$(basename "$patch")"
    patch -d "$SRC" -p1 --forward --quiet < "$patch"
  done
  touch "$SRC/.patched"
fi

cd "$SRC"
if [ ! -f out/Release/build.ninja ]; then
  # What android-configure does, plus --ninja and no npm/corepack. The host toolset (V8's mksnapshot,
  # torque…, built for the target's instruction set through V8's simulator) is compiled with the host's
  # clang, the target with the NDK's.
  CC="$TOOLCHAIN/bin/$TRIPLE$ANDROID_API-clang" \
  CXX="$TOOLCHAIN/bin/$TRIPLE$ANDROID_API-clang++" \
  CC_host=${CC_host:-clang} CXX_host=${CXX_host:-clang++} LINK_host=${LINK_host:-clang++} \
  LDFLAGS="-static-libstdc++" \
  GYP_DEFINES="target_arch=$ARCH v8_target_arch=$ARCH android_target_arch=$ARCH host_os=linux OS=android android_ndk_path=$NDK" \
  PATH="$TOOLCHAIN/bin:$PATH" \
    $PYTHON configure \
      --dest-cpu=$DEST_CPU --dest-os=android --cross-compiling \
      --openssl-no-asm \
      --ninja \
      --without-npm --without-corepack
fi

# Not with the NDK on PATH: host clang would then link with the NDK's ld (lld), which fails on V8's libatomic use
ninja -C out/Release -j "$JOBS" node

NAME=node-v$VERSION-android-$ARCH
STAGE=$WORK/$NAME
rm -rf "$STAGE"
mkdir -p "$STAGE"
"$TOOLCHAIN/bin/llvm-strip" -o "$STAGE/node" out/Release/node
cp LICENSE "$STAGE/LICENSE"
{
  echo "Node $VERSION for Android $ARCH (API $ANDROID_API+), built by https://github.com/sigmaSd/node-android"
  echo "NDK $NDK_VERSION"
  echo "Patches: $(cd "$PATCHES" && ls ./*.patch | xargs -n1 basename | tr '\n' ' ')"
  echo "Needs: $("$TOOLCHAIN/bin/llvm-readelf" -d "$STAGE/node" | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p' | tr '\n' ' ')"
} > "$STAGE/BUILD-INFO"
cat "$STAGE/BUILD-INFO"

tar -C "$WORK" -cJf "$OUT/$NAME.tar.xz" "$NAME"
(cd "$OUT" && sha256sum "$NAME.tar.xz" > "$NAME.tar.xz.sha256")
ls -l "$OUT/$NAME.tar.xz"
