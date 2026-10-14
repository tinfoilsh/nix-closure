{
  description = "Nix closures packed as modelwrap artifacts";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [
          (final: _: {
            droid = final.callPackage ./pkgs/droid.nix { };
          })
        ];
        config.allowUnfree = true;
      };
    in {
      packages.${system} = {
        # nix is in here because the CVM mounts this pack as the lower layer of
        # a local-overlay store, which Lix does not implement.
        closure = pkgs.buildEnv {
          name = "sandbox-toolchain";
          # A set this wide collides on shared names (cc, parallel, ...).
          # toolchain.nix demotes the loser of every collision that matters;
          # this only keeps the long tail from failing the build.
          ignoreCollisions = true;
          paths = [ pkgs.nix ] ++ import ./toolchain.nix { inherit pkgs nixpkgs; };
        };

        # Pinned: the packer must be the nix the closure carries.
        inherit (pkgs) nix sqlite;
      };
    };
}
