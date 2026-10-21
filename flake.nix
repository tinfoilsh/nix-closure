{
  description = "Nix closures packed as modelwrap artifacts";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nixgl = {
      url = "github:nix-community/nixGL";
      flake = false;
    };
    # Newer trees break the toolchain build (semgrep, python3.14 test failures); take only opencode 2.
    nixpkgs-opencode.url = "github:NixOS/nixpkgs/02c087f3fe673c9e317f206a627cb6b910336dbe";
  };

  outputs =
    { nixpkgs, nixgl, nixpkgs-opencode, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [
          (final: prev: {
            # Avro 1.12 hits GCC 16's speculative-devirtualization array-bounds warning.
            avro-cpp = prev.avro-cpp.override { stdenv = final.gcc15Stdenv; };
            # glibc 2.44's C23 declarations must precede TinyCThread's compatibility macros.
            libserdes = prev.libserdes.overrideAttrs (old: {
              # Avro 1.12's public headers assume fmt's header-only mode.
              env.CPPFLAGS = "-DFMT_HEADER_ONLY";
              postPatch = old.postPatch + ''
                substituteInPlace src/tinycthread.h --replace-fail '#include <time.h>' \
                  '#include <time.h>
                #include <stdlib.h>
                #undef ONCE_FLAG_INIT'
              '';
            });
            opencode = nixpkgs-opencode.legacyPackages.${system}.opencode;
            droid = final.callPackage ./pkgs/droid.nix { };
            envoy = final.callPackage ./pkgs/envoy.nix { };
            qdrant = final.callPackage ./pkgs/qdrant.nix { };
            selkies = final.callPackage ./pkgs/selkies.nix { };
            nixgl = import nixgl {
              pkgs = final;
              enable32bits = false;
              enableIntelX86Extensions = false;
            };
            sandbox-desktop = import ./desktop.nix { pkgs = final; };
          })
        ];
        config.allowUnfree = true;
        # Checkov only verifies signatures; CVE-2024-23342 affects signing and key generation.
        config.permittedInsecurePackages = [ "python3.14-ecdsa-0.19.2" ];
      };
    in
    {
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
        inherit (pkgs) nix sqlite selkies;
        desktop = pkgs.sandbox-desktop;
      };
    };
}
