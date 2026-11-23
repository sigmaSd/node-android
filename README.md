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
This is what [nodeapk](https://github.com/sigmaSd/nodeapk) does (it packs a Node app into an APK).

**Over adb**, to try it:

```bash
tar -xJf node-v24.22.3-android-arm64.tar.xz
adb push node-v24.22.3-android-arm64/node /data/local/tmp/
adb shell 'cd /data/local/tmp && TMPDIR=$PWD HOME=$PWD ./node -e "console.log(process.versions)"'
```

## Tested

v24.22.3 arm64 on a Xiaomi 2409BRN2CA (Android 16), run by an app (nodeapk's demo):

- **Works**: `node:http` server on 127.0.0.1, `node:sqlite`, `crypto` (X25519, Ed25519, scrypt, WebCrypto),
  `fetch` over HTTPS (bundled CA certificates), `dns.lookup`, `node:dgram` broadcast (send and receive),
  `fs.watch`, `os.networkInterfaces()`, `child_process` (`/system/bin/sh`), `worker_threads`, full-ICU
  `Intl`, `zlib` (gzip, brotli), TypeScript entry files (type stripping), uncaught errors on stderr.
- **Android's limits**: `os.cpus()` returns `[]` (`/proc/stat` is closed to apps), MAC addresses in
  `os.networkInterfaces()` are zeros.
- **Doesn't work**: `dns.resolve*()` (c-ares) fails with `ECONNREFUSED`: with no `/etc/resolv.conf` it has
  no DNS servers and tries 127.0.0.1. Use `dns.lookup` (what `http`, `fetch` and `net` use), or pass the
  servers in with `dns.setServers()`.
- **Startup**: `node -e 0` takes ~0.25 s on that phone.

x64 hasn't been run yet.

## Known limits

- Built with `--openssl-no-asm` (as Node's `android-configure` does): OpenSSL doesn't use the CPU's crypto
  instructions; scrypt N=2^15 takes ~200 ms on the phone above.
- No startup snapshot or built-in code cache (they can't be generated while cross-compiling): loading
  built-in modules costs more at startup than on desktop Node.
- Android's app freezers suspend an app's processes in the background, Node included: background work needs
  a foreground service in the app.

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
