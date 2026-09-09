# The package set the pack carries. Grouped by what an agent reaches for, so a
# reviewer can see what a group buys before deciding whether it earns its bytes.
{ pkgs, nixpkgs }:

let
  inherit (pkgs) lib;
  inherit (lib) lowPrio;

  # Exported by the profile script rather than baked in: buildEnv produces a
  # tree, not an environment, so the shell has to be told where these live.
  profile = pkgs.writeTextFile {
    name = "sandbox-profile";
    destination = "/etc/profile.d/50-sandbox.sh";
    text = ''
      export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
      export NIX_SSL_CERT_FILE="$SSL_CERT_FILE"
      export LOCALE_ARCHIVE=${pkgs.glibcLocales}/lib/locale/locale-archive
      export TZDIR=${pkgs.tzdata}/share/zoneinfo
      export LANG=C.UTF-8
    '';
  };

  # Pins `nixpkgs` to the tree this pack was built from, so `nix run nixpkgs#x`
  # and `nix-shell -p x` evaluate to paths the pack already holds.
  registry = pkgs.writeTextFile {
    name = "sandbox-registry";
    destination = "/etc/nix/registry.json";
    text = builtins.toJSON {
      version = 2;
      flakes = [{
        from = { type = "indirect"; id = "nixpkgs"; };
        to = { type = "path"; path = "${nixpkgs}"; };
      }];
    };
  };

  languages = with pkgs; [
    bun
    deno
    go
    jdk21
    nodejs
    pnpm
    python313
    ruby
    uv
  ];

  # cargo/rustc/rust-analyzer come from nixpkgs so they are in the closure;
  # rustup is demoted because its shims shadow them and resolve nothing until
  # it has downloaded a toolchain, which the enclave has no network for.
  rust = [
    pkgs.cargo
    pkgs.clippy
    pkgs.rust-analyzer
    pkgs.rustc
    pkgs.rustfmt
    (lowPrio pkgs.rustup)
  ];

  # clang is demoted so gcc owns cc/c++/cpp; clang-tools carries clangd and
  # clang-format, which is why neither appears again under servers/formatters.
  # stdenv has no bin/; it is here because `nix-shell -p` realises it.
  native = [
    pkgs.binutils
    pkgs.clang-tools
    pkgs.gcc
    pkgs.gnumake
    pkgs.llvm
    pkgs.pkg-config
    pkgs.stdenv
    (lowPrio pkgs.clang)
  ];

  agents = with pkgs; [
    claude-code
    codex
    droid
    hermes-agent
    pi-coding-agent
    qwen-code
  ];

  servers = with pkgs; [
    basedpyright
    bash-language-server
    gopls
    lua-language-server
    marksman
    nixd
    taplo
    typescript-language-server
    yaml-language-server
  ];

  checkers = with pkgs; [
    actionlint
    golangci-lint
    hadolint
    mypy
    ruff
    shellcheck
    typos
    yamllint
  ];

  formatters = with pkgs; [
    nixfmt
    prettier
    shfmt
  ];

  dataAndText = with pkgs; [
    dasel
    duckdb
    ghostscript
    graphviz
    gron
    imagemagick
    jq
    mermaid-cli
    miller
    pandoc
    poppler-utils
    qsv
    sqlite
    tesseract
    yq-go
  ];

  networkAndWeb = with pkgs; [
    croc
    curl
    dnsutils
    grpcurl
    mitmproxy
    mkcert
    netcat-gnu
    openssl
    rclone
    socat
    step-cli
    tcpdump
    websocat
    wget
    xh
  ];

  # Backend code an agent cannot run is code it cannot verify.
  # garage rather than minio for S3: nixpkgs marks minio insecure since
  # upstream abandoned it, and unauthenticated object write does not belong in
  # a pack whose hash is attested.
  services = with pkgs; [
    garage
    mariadb
    postgresql
    valkey
  ];

  debugAndProfile = with pkgs; [
    delve
    gdb
    hyperfine
    lldb
    ltrace
    perf
    py-spy
    strace
    valgrind
  ];

  # moreutils is demoted so GNU parallel owns `parallel`.
  shell = [
    pkgs.bashInteractive
    pkgs.coreutils
    pkgs.direnv
    pkgs.entr
    pkgs.expect
    pkgs.findutils
    pkgs.gawk
    pkgs.git
    pkgs.gnused
    pkgs.gnutar
    pkgs.just
    pkgs.p7zip
    pkgs.parallel
    pkgs.tmux
    pkgs.unzip
    pkgs.watchexec
    pkgs.zstd
    (lowPrio pkgs.moreutils)
  ];

  # Locales, certs and zoneinfo have no bin/, but the profile script above is
  # dead without them. man-db is here because man-pages needs a reader.
  runtime = with pkgs; [
    cacert
    glibc
    glibcLocales
    linuxHeaders
    man-db
    man-pages
    man-pages-posix
    profile
    registry
    tzdata
  ];

  cloud = with pkgs; [
    awscli2
    azure-cli
    dive
    doctl
    flyctl
    google-cloud-sdk
    k9s
    kubectl
    kubernetes-helm
    opentofu
    skopeo
    wrangler
  ];
in
lib.concatLists [
  agents
  checkers
  cloud
  dataAndText
  debugAndProfile
  formatters
  languages
  native
  networkAndWeb
  runtime
  rust
  servers
  services
  shell
]
