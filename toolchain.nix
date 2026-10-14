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
    beamPackages.elixir
    bun
    deno
    dotnet-sdk_10
    go
    gradle
    jdk21
    kotlin
    lua5_4
    maven
    nodejs
    perl
    php
    phpPackages.composer
    pnpm
    python313
    ruby
    typescript
    uv
    yarn
    zig
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
    pkgs.autoconf
    pkgs.automake
    pkgs.binutils
    pkgs.clang-tools
    pkgs.cmake
    pkgs.gcc
    pkgs.gnumake
    pkgs.libtool
    pkgs.llvm
    pkgs.meson
    pkgs.ninja
    pkgs.pkg-config
    pkgs.protobuf
    pkgs.stdenv
    (lowPrio pkgs.clang)
  ];

  agents = with pkgs; [
    amp-cli
    antigravity-cli
    claude-code
    codex
    crush
    cursor-cli
    droid
    github-copilot-cli
    goose-cli
    opencode
    pi-coding-agent
    qwen-code
  ];

  servers = with pkgs; [
    basedpyright
    bash-language-server
    dockerfile-language-server
    elixir-ls
    gopls
    jdt-language-server
    kotlin-language-server
    lua-language-server
    marksman
    nixd
    phpactor
    ruby-lsp
    sqls
    svelte-language-server
    tailwindcss-language-server
    taplo
    terraform-ls
    typescript-language-server
    vscode-langservers-extracted
    vue-language-server
    yaml-language-server
    zls
  ];

  checkers = with pkgs; [
    actionlint
    biome
    buf
    cargo-audit
    cargo-deny
    codespell
    deadnix
    eslint
    gitleaks
    golangci-lint
    hadolint
    kubeconform
    markdownlint-cli2
    mypy
    osv-scanner
    rubocop
    ruff
    semgrep
    shellcheck
    sqlfluff
    statix
    tflint
    trivy
    typos
    yamllint
  ];

  formatters = with pkgs; [
    gofumpt
    google-java-format
    ktfmt
    nixfmt
    prettier
    shfmt
    stylua
  ];

  dataAndText = with pkgs; [
    dasel
    duckdb
    exiftool
    ffmpeg-headless
    fx
    ghostscript
    graphviz
    gron
    hexyl
    htmlq
    imagemagick
    jless
    jo
    jq
    libxml2
    mermaid-cli
    miller
    pandoc
    poppler-utils
    qpdf
    qsv
    sqlite
    sqlite-utils
    tesseract
    typst
    xmlstarlet
    yq-go
  ];

  # chromium is already in the closure as mermaid-cli's renderer.
  networkAndWeb = with pkgs; [
    aria2
    chromium
    croc
    curl
    dnsutils
    grpcurl
    hurl
    iproute2
    iputils
    mitmproxy
    mkcert
    mtr
    netcat-gnu
    nmap
    openssh
    openssl
    rclone
    rsync
    socat
    step-cli
    tcpdump
    traceroute
    websocat
    wget
    xh
  ];

  # Backend code an agent cannot run is code it cannot verify.
  # garage rather than minio for S3: nixpkgs marks minio insecure since
  # upstream abandoned it, and unauthenticated object write does not belong in
  # a pack whose hash is attested.
  services = with pkgs; [
    caddy
    etcd
    garage
    mailpit
    mariadb
    nats-server
    nginx
    postgresql
    valkey
  ];

  debugAndProfile = with pkgs; [
    bpftrace
    delve
    gdb
    htop
    hyperfine
    lldb
    lsof
    ltrace
    perf
    py-spy
    rr
    samply
    strace
    valgrind
  ];

  # moreutils is demoted so GNU parallel owns `parallel`.
  shell = [
    pkgs.age
    pkgs.ast-grep
    pkgs.bashInteractive
    pkgs.bat
    pkgs.bc
    pkgs.bzip2
    pkgs.coreutils
    pkgs.delta
    pkgs.difftastic
    pkgs.diffutils
    pkgs.direnv
    pkgs.entr
    pkgs.expect
    pkgs.fd
    pkgs.file
    pkgs.findutils
    pkgs.fzf
    pkgs.gawk
    pkgs.gh
    pkgs.git
    pkgs.git-lfs
    pkgs.gnugrep
    pkgs.gnupg
    pkgs.gnused
    pkgs.gnutar
    pkgs.gzip
    pkgs.jujutsu
    pkgs.just
    pkgs.less
    pkgs.ncdu
    pkgs.nix-output-monitor
    pkgs.nix-tree
    pkgs.nurl
    pkgs.p7zip
    pkgs.parallel
    pkgs.patch
    pkgs.pre-commit
    pkgs.procps
    pkgs.psmisc
    pkgs.pv
    pkgs.ripgrep
    pkgs.sd
    pkgs.sops
    pkgs.time
    pkgs.tmux
    pkgs.tokei
    pkgs.tree
    pkgs.unzip
    pkgs.util-linux
    pkgs.vim
    pkgs.watchexec
    pkgs.which
    pkgs.xz
    pkgs.zip
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
    cosign
    crane
    dive
    doctl
    flyctl
    google-cloud-sdk
    k9s
    kubectl
    kubernetes-helm
    opentofu
    oras
    skopeo
    syft
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
