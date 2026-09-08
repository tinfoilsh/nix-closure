{
  description = "Nix closures packed as modelwrap artifacts";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { nixpkgs, ... }:
    let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
    in {
      # nix is in here because the CVM mounts this pack as the lower layer of
      # a local-overlay store, which Lix does not implement.
      packages.x86_64-linux.closure = pkgs.buildEnv {
        name = "sandbox-toolchain";
        paths = [ pkgs.nix pkgs.bashInteractive pkgs.coreutils pkgs.bun ];
      };

      # Pinned because it rewrites the database that goes into the root hash.
      packages.x86_64-linux.sqlite = pkgs.sqlite;
    };
}
