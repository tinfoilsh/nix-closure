# nix-closure

Pack a Nix closure into an artifact for [modelwrap](https://github.com/tinfoilsh/modelwrap). A CVM mounts the artifact the same way it mounts model weights, and the attested config pins its hash.

```bash
./pack.sh            # packs .#closure
./pack.sh .#other    # any flake attr with one output path
```

The staged tree is a function of the closure alone. The store db is rebuilt from `nix-store --dump-db` with the nix the closure carries, which keeps copy order, substituter signatures, registration times and the staging path out of the root hash. What is left is whether the closure's own paths build bit for bit, so a verifier who substitutes them from the same cache reproduces the artifact.

`.#closure` is a `buildEnv` over the set in [`toolchain.nix`](toolchain.nix): coding agents, language runtimes, language servers, checkers, formatters, data and text tools, network tools, local Postgres/MariaDB/Valkey/Garage, debuggers and profilers, a shell substrate, and the cloud CLIs. Everything comes from nixpkgs except `droid`, which Factory ships only as a prebuilt binary, and `hermes-agent`, which is built by upstream's own flake.

The set is wide enough to collide on shared names. `toolchain.nix` demotes the loser where the winner matters (gcc owns `cc`, GNU parallel owns `parallel`, nixpkgs' rustc owns `rustc` over rustup's shim) and `ignoreCollisions` absorbs the rest.

## Using it in the container

The pack carries a profile, `nix/var/nix/profiles/default`, that points at the closure. It is the one name for the closure that does not carry its hash, so link `/nix/var/nix/profiles/default` in the container to it and let the image refer to that. Source `<profile>/etc/profile.d/nix-daemon.sh`, which nix ships and which puts the profile on `PATH`, and `<profile>/etc/profile.d/50-sandbox.sh`, which sets `SSL_CERT_FILE`, `LOCALE_ARCHIVE`, `TZDIR` and `LANG`. Those cannot be baked into a store path.

Link `/bin/bash` and `/usr/bin/env` to the profile. Scripts hardcode both, and neither can come from the pack itself: the pack is mounted at `/nix`, so `/bin` and `/usr/bin` belong to the container's rootfs.

`<profile>/etc/nix/registry.json` pins `nixpkgs` to the tree the pack was built from. Point `flake-registry` in `nix.conf` at it and `nix run nixpkgs#x`, `nix shell nixpkgs#x` and `nix-shell -p x` evaluate to the paths the pack already holds, so anything it carries is neither fetched nor built again. `stdenv` is in the closure for the same reason: `nix-shell -p` realises it.

`rustup` is in the closure because it was asked for, but its shims resolve nothing until they have downloaded a toolchain, which the enclave has no network for. Use the nixpkgs `cargo` and `rustc` that the closure carries.

The pack lands in `output/nix/<name>/<storeHash>.{mpk,info}`. Put the `.info` reference in the attested config, declare the model `exec: true`, and grant it to the container that stacks it.

The CVM mounts the pack as the read-only half of a [local-overlay store](https://nix.dev/manual/nix/latest/store/types/local-overlay-store). Its paths are already valid, so the enclave copies nothing at start. New paths go to the volume.

Use a modelwrap release that skips the `--model-dir` hash when the model argument carries an `@revision`. Older releases fail on the store symlinks in the pack.
