# nix-closure

Pack a Nix closure into an artifact for [modelwrap](https://github.com/tinfoilsh/modelwrap). A CVM mounts the artifact the same way it mounts model weights, and the attested config pins its hash.

```bash
./pack.sh            # packs .#closure
./pack.sh .#other    # any flake attr with one output path
```

The pack lands in `output/nix/<name>/<storeHash>.{mpk,info}`. Put the `.info` reference in the attested config and declare the pack under `volumes[].overlays`.

The CVM mounts the pack as the read-only half of a [local-overlay store](https://nix.dev/manual/nix/latest/store/types/local-overlay-store). Its paths are already valid, so the enclave copies nothing at start. New paths go to the volume.

Use a modelwrap release that skips the `--model-dir` hash when the model argument carries an `@revision`. Older releases fail on the store symlinks in the pack.
