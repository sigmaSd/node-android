# Patches

`build.sh` applies `patches/<major>/*.patch` in order (by file name) to the Node source. The `24/` set was
written against Node 24.22.3. All but four come from Termux's `nodejs-lts` package
(https://github.com/termux/termux-packages/tree/master/packages/nodejs-lts), which builds that same version.
Termux's patches that only matter to Termux (its prefix instead of `/tmp`, `/system/bin/sh`, system
ICU/OpenSSL, its `getaddrinfo` workaround) are left out: this build bundles Node's own dependencies, and
whoever starts Node sets `TMPDIR`.

| Patch | From | Why |
| --- | --- | --- |
| `avoid-ficlone-ioctl.patch` | Termux | `fs.copyFile` with `COPYFILE_FICLONE` must not try the FICLONE ioctl on Android |
| `configure.py-file-order.patch` | node-android | `configure` lists ICU's sources in the disk's own order, which becomes their link order: sorted, so a release rebuilds bit for bit on another machine |
| `configure.py-section-ordering.patch` | node-android | `process.config`, built into `node`, has `node_section_ordering_info` only when the build machine has `ld.gold` (Ubuntu does, Debian doesn't): set the same way everywhere, so a release rebuilds bit for bit on another machine (the `reproduce` workflow) |
| `deps-uvwasi-src-uvwasi.c.patch` | Termux | enables WASI `fd_readdir` on Android (bionic has `seekdir`/`telldir`) |
| `deps-v8-src-trap-handler-trap-handler.h.patch` | Termux (Node ships the same idea in `android-patches/`, but for an older V8) | WebAssembly's trap handler is off on Android (V8 refuses it there); without this, the host tools built for the arm64 simulator turn it on and trip that check |
| `deps-zlib-zlib.gyp-getauxval.patch` | node-android | Node's bundled zlib detects CRC32/PMULL on Android with the NDK's old `cpufeatures` library, which nothing builds (link error); bionic's `getauxval`, as on Linux, does the same |
| `fix_multiple_definitions.patch` | Termux | libuv defines `uv_get_free_memory` twice on Android (link error) |
| `src-debug_utils.cc-stderr.patch` | node-android | Node sends its own stderr messages (fatal errors…) to logcat on Android; a parent process (an app shell, `adb shell`) reads Node's stderr, so they stay on stderr |
| `src-node_internals.h.patch` | Termux | `process.getuid()`, `getgid()`… exist on Android too |
| `src-node_report.cc.patch` | Termux | `process.report` writes an empty `cpus` list when `/proc/stat` can't be read (apps can't, since Android 8) |
| `tools-gyp-pylib-gyp-generator-ninja.py.patch` | Termux | with `--ninja`, host and target builds generate files to the same path; this separates them |
| `tools-v8_gypfiles-toolchain.gypi.patch` | Termux | V8 prints to stdout rather than logcat; drops `-mbranch-protection` |
| `tools-v8_gypfiles-v8.gyp.patch` | Termux | links `-latomic` with clang on Android; lists `platform-linux.h` |

Termux's patches are under the license of the package they patch (Node's, MIT).

## A new major

Copy the previous set to `patches/<major>/`, run `./build.sh <version> arm64` and fix what no longer applies
(Termux usually has the updated patch in `packages/nodejs` or `packages/nodejs-lts`). The daily workflow
starts building a major as soon as its folder exists.
