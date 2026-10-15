# nix-closure

Pack a Nix closure into an artifact for [modelwrap](https://github.com/tinfoilsh/modelwrap). A CVM mounts the artifact the same way it mounts model weights, and the attested config pins its hash.

```bash
./pack.sh            # packs .#closure
./pack.sh .#other    # any flake attr with one output path
```

The staged tree is a function of the closure alone. The store db is rebuilt from `nix-store --dump-db` with the nix the closure carries, which keeps copy order, substituter signatures, registration times and the staging path out of the root hash. What is left is whether the closure's own paths build bit for bit, so a verifier who substitutes them from the same cache reproduces the artifact.

`.#closure` is a `buildEnv` over the set in [`toolchain.nix`](toolchain.nix): coding agents, language runtimes and build tools, language servers, checkers, formatters, data and text tools, network tools and a desktop, local databases, web servers and queues, debuggers and profilers, a shell substrate, and the cloud and supply-chain CLIs. Most packages come from nixpkgs. The local definitions in `pkgs/` pin upstream releases for Droid, Envoy, Qdrant, and Selkies; nixGL is a locked source input evaluated with this closure's nixpkgs.

The set is wide enough to collide on shared names. `toolchain.nix` demotes the loser where the winner matters (gcc owns `cc`, GNU parallel owns `parallel`, nixpkgs' rustc owns `rustc` over rustup's shim) and `ignoreCollisions` absorbs the rest.

## Desktop

Run `sandbox-desktop` as the sandbox user, then forward its loopback port:

```sh
ssh -N -L 6080:127.0.0.1:6080 <sandbox-ssh-alias>
```

Open `http://127.0.0.1:6080/`. The Selkies client streams the Xfce desktop and
sound over WebSocket, so the same SSH forward carries everything. Enable Gaming
mode in its sidebar for pointer lock and relative mouse input; Escape releases
the pointer. Browser audio may require a click before playback starts.
Existing `/vnc.html` bookmarks redirect to the new client.

The session uses nixGL's Mesa wrapper with CPU OpenGL/EGL and Lavapipe Vulkan.
SDL uses EGL because headless GLX does not expose the sRGB visuals some games
require. Xorg's dummy driver supports browser-driven resizing. PulseAudio owns
a private Unix socket and a virtual output device; ALSA defaults to that server.
No GPU or sound device is required. Webcam and gamepad forwarding are disabled.
Software rendering and video encoding share the CPU; the stream defaults to
30 fps.

Launch applications from the desktop so they inherit its graphics and audio
environment. `SANDBOX_DISPLAY`, `SANDBOX_DESKTOP_PORT`, and `SANDBOX_DESKTOP_SIZE`
select the display, port, and initial resolution. Ctrl-C or Xfce Log Out stops
the display, streamer, and audio server. Run in tmux to keep the session after
disconnecting SSH. The HTTP listener is loopback-only and relies on the SSH
tunnel for authentication.

Build with `nix build .#desktop`; `nix build .#selkies` also checks the native
encoder imports and packaged web assets. Selkies is packaged locally from its
hash-pinned native release, including the matching web client, Python
dependencies, pixelflux, and pcmflux. It does not download dependencies at launch.
Publishing a new full closure pack and updating the sandbox template's `repo`
and `mwp` references are separate rollout steps; existing VMs keep their mounted
pack until updated.

## Using it in the container

The pack carries a profile, `nix/var/nix/profiles/default`, that points at the closure. It is the one name for the closure that does not carry its hash, so link `/nix/var/nix/profiles/default` in the container to it and let the image refer to that. Source `<profile>/etc/profile.d/nix-daemon.sh`, which nix ships and which puts the profile on `PATH`, and `<profile>/etc/profile.d/50-sandbox.sh`, which sets `SSL_CERT_FILE`, `LOCALE_ARCHIVE`, `TZDIR` and `LANG`. Those cannot be baked into a store path.

Link `/bin/bash` and `/usr/bin/env` to the profile. Scripts hardcode both, and neither can come from the pack itself: the pack is mounted at `/nix`, so `/bin` and `/usr/bin` belong to the container's rootfs.

`<profile>/etc/nix/registry.json` pins `nixpkgs` to the tree the pack was built from. Point `flake-registry` in `nix.conf` at it and `nix run nixpkgs#x`, `nix shell nixpkgs#x` and `nix-shell -p x` evaluate to the paths the pack already holds, so anything it carries is neither fetched nor built again. `stdenv` is in the closure for the same reason: `nix-shell -p` realises it.

`rustup` is in the closure because it was asked for, but its shims resolve nothing until they have downloaded a toolchain, which the enclave has no network for. Use the nixpkgs `cargo` and `rustc` that the closure carries.

The pack lands in `output/nix/<name>/<storeHash>.{mpk,info}`. Put the `.info` reference in the attested config, declare the model `exec: true`, and grant it to the container that stacks it.

The CVM mounts the pack as the read-only half of a [local-overlay store](https://nix.dev/manual/nix/latest/store/types/local-overlay-store). Its paths are already valid, so the enclave copies nothing at start. New paths go to the volume.

Use a modelwrap release that skips the `--model-dir` hash when the model argument carries an `@revision`. Older releases fail on the store symlinks in the pack.
