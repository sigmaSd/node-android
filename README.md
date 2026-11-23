# node-android

Node.js for Android: one self-contained `node` executable per architecture (arm64 for phones, x64 for the
emulator), built from Node's official source with the NDK. Node has no official Android binaries; its own
Android build path is experimental and untested upstream.

The releases follow Node on their own: a daily workflow builds every new release of the supported lines and
publishes it here as `v<node version>`.

| Supported | Patches | Android |
| --- | --- | --- |
| Node 24 (LTS) | [`patches/24/`](patches/README.md) | 9 (API 28) and later |

## What's in a release

`node-v<version>-android-<arch>.tar.xz`, with:

- `node`: the executable. OpenSSL, ICU (full, all locales), zlib, libuv, c-ares, nghttp2 and SQLite are
  compiled in, libc++ is static: it needs only Android's own `libc`, `libm`, `libdl` and `liblog`. No npm or
  corepack.
- `LICENSE`: Node's.
- `BUILD-INFO`: version, NDK, patches, linked libraries.

Each archive has a `.sha256` next to it. The source is checked against Node's GPG-signed checksums before
building.

## Using it

**Inside an app.** Android 10+ won't execute files from an app's data folder; ship `node` in the APK as
`lib/<abi>/libnode.so` with `android:extractNativeLibs="true"`, and run it from
`getApplicationInfo().nativeLibraryDir`. Set `HOME` and `TMPDIR` to the app's folders: Android has no `/tmp`.
This is what nodeapk (an APK packager for Node apps, in the works) does.

**Over adb**, to try it:

```bash
tar -xJf node-v24.22.3-android-arm64.tar.xz
adb push node-v24.22.3-android-arm64/node /data/local/tmp/
adb shell 'cd /data/local/tmp && TMPDIR=$PWD HOME=$PWD ./node -e "console.log(process.versions)"'
```

## Known limits

- Built with `--openssl-no-asm` (as Node's `android-configure` does): OpenSSL doesn't use the CPU's crypto
  instructions, so AES/SHA are slower than on desktop Node.
- No startup snapshot (it can't be generated while cross-compiling): startup is slower than desktop Node.

## Building it yourself

Linux x86_64 with clang, ninja, Python 3.10–3.14, gpgv and the NDK
(`sdkmanager "ndk;29.0.14206865"`):

```bash
JOBS=8 ./build.sh 24.22.3 arm64      # → out/node-v24.22.3-android-arm64.tar.xz
```

About an hour on 12 cores, two on a GitHub runner; each compile job can take ~1 GB of memory.

## Notes

- A new major needs its own patch set first (see [patches/README.md](patches/README.md)). If an automatic
  build fails, nothing is published and an issue is opened.
- GitHub disables scheduled workflows in repositories with no commits for 60 days; re-enable it in the
  Actions tab (or push anything) if releases stop appearing.
