# Dependency provenance

The core has no third-party runtime dependencies. C++17 standard headers supply integer/size types only. There are no Node/npm packages, remote JS modules, Emscripten runtime or WASI imports.

The native Godot bridge uses one MIT-licensed generated C-interface header, copied from the existing workstation Godot C++ binding checkout. `dependencies.json` pins its upstream repository commit, generation source and exact SHA-256; the build refuses a mismatched header. The original copyright/license notice stays in the header. No godot-cpp library, generated engine class bindings or dependency download is required. Godot itself is the external engine runtime.

The tested system tools were GCC 16.2.1, Clang/wasm-ld 23.1.3, CMake 4.4.4, Deno 2.9.7 and managed Godot 4.7. Tool binaries are supplied by the workstation, not vendored or downloaded by build scripts. `build/core-build.json` records exact compiler versions/identities, sources and output hashes; it is a local freshness receipt, not a claim that all toolchains produce identical code. No toolchain installer runs during play/discovery.

CraftPix art is not a dependency distributed here. The private importer/manifest contract remains in `specs/assets-hosting.md`. Never commit raw vendor PNG/PSD files.
