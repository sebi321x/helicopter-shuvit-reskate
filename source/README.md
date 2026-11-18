# Companion runtime source

`reskate-20261116-air-gravity.patch` modifies the open-source ReSkate runtime at upstream tag `20261116`. The patch and modified runtime are under GNU GPL version 3. ReSkate is copyright its contributors. See the upstream External directory for its third-party notices.

Get the [ReSkate 20261116 source](https://github.com/Dingo-Shenanigans/ReSkate/archive/refs/tags/20261116.tar.gz) and apply `reskate-20261116-air-gravity.patch` and `release-build.patch` with `git apply` or `patch -p1` from the source root. Run `python3 normalize-examples.py <upstream-source-directory>` to normalize the music setup path examples. The archive used for this build has SHA-256 `4363647f2ffbfa8aaac87ae2964b2ff71efbcdd1433f6783e30ce8e6076f297f`. Omit the optional `assets/` directory to build the companion runtime without upstream artwork. The reference Windows build uses the `vs2022-x64` preset and the `dingosdk_runtime` target.

```sh
cmake --preset vs2022-x64 -DDINGOSDK_VERSION=20261116 -DDINGOSDK_MOD_ID=Helicopter_Shove_It -DDINGOSDK_MOD_VERSION=0.4.1 -DDINGOSDK_CRASH_REPORT_URL:STRING= -DDINGOSDK_LAUNCHER_AUTO_UPDATE=OFF
cmake --build --preset release --target dingosdk_runtime
```

The macOS cross-build uses Clang in MSVC mode, an x64 Windows SDK sysroot, and the Rust `x86_64-pc-windows-msvc` target. It remaps build paths at compile time. `SpotifyHelper/Cargo.lock` pins the Rust dependencies. The release cross-build sets SOURCE_DATE_EPOCH=1794787200 and TZ=UTC during compilation. The startup banner uses the upstream release date, November 16, 2026 at 00:00:00 UTC. Recompile Engine/Core/Log/banner.cpp when changing the epoch in an existing build directory. Debug symbols are omitted.
