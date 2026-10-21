# The package set the pack carries. Grouped by what an agent reaches for, so a
# reviewer can see what a group buys before deciding whether it earns its bytes.
{
  pkgs,
  nixpkgs,
  cacert,
}:

let
  inherit (pkgs) lib;
  inherit (lib) lowPrio;

  # Exported by the profile script rather than baked in: buildEnv produces a
  # tree, not an environment, so the shell has to be told where these live.
  profile = pkgs.writeTextFile {
    name = "sandbox-profile";
    destination = "/etc/profile.d/50-sandbox.sh";
    text = ''
      export SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt
      export NIX_SSL_CERT_FILE="$SSL_CERT_FILE"
      export LOCALE_ARCHIVE=${pkgs.glibcLocales}/lib/locale/locale-archive
      export TZDIR=${pkgs.tzdata}/share/zoneinfo
      export LANG=C.UTF-8
      export PLAYWRIGHT_BROWSERS_PATH=${pkgs.playwright-driver.browsers}
      export PRISMA_SCHEMA_ENGINE_BINARY=${pkgs.prisma-engines}/bin/schema-engine
      export JAVA_HOME_17=${pkgs.jdk17}
      export JAVA_HOME_21=${pkgs.jdk21}
      export JAVA_HOME_25=${pkgs.jdk25}

      case $- in
        *i*)
          if [ -z "''${_SANDBOX_SHELL_INITIALIZED:-}" ]; then
            if [ -n "''${BASH_VERSION:-}" ]; then
              . ${pkgs.bash-completion}/share/bash-completion/bash_completion
              eval "$(${pkgs.carapace}/bin/carapace _carapace bash)"
              eval "$(${pkgs.zoxide}/bin/zoxide init bash)"
              case ":$SHELLOPTS:" in
                *:emacs:*|*:vi:*) eval "$(${pkgs.atuin}/bin/atuin init bash)" ;;
              esac
              eval "$(${pkgs.starship}/bin/starship init bash)"
              _SANDBOX_SHELL_INITIALIZED=1
            elif [ -n "''${ZSH_VERSION:-}" ]; then
              autoload -Uz compinit && compinit
              eval "$(${pkgs.carapace}/bin/carapace _carapace zsh)"
              eval "$(${pkgs.zoxide}/bin/zoxide init zsh)"
              eval "$(${pkgs.atuin}/bin/atuin init zsh)"
              eval "$(${pkgs.starship}/bin/starship init zsh)"
              _SANDBOX_SHELL_INITIALIZED=1
            fi
          fi
          ;;
      esac
    '';
  };

  # Pins `nixpkgs` to the tree this pack was built from, so `nix run nixpkgs#x`
  # and `nix-shell -p x` evaluate to paths the pack already holds.
  registry = pkgs.writeTextFile {
    name = "sandbox-registry";
    destination = "/etc/nix/registry.json";
    text = builtins.toJSON {
      version = 2;
      flakes = [
        {
          from = {
            type = "indirect";
            id = "nixpkgs";
          };
          to = {
            type = "path";
            path = "${nixpkgs}";
          };
        }
      ];
    };
  };

  python = pkgs.python313.withPackages (
    p: with p; [
      numpy
      pandas
      polars
      pyarrow
      matplotlib
      scipy
      scikit-learn
      requests
      httpx
      beautifulsoup4
      lxml
      pyyaml
      pillow
      openpyxl
      python-docx
      pypdf
      ipython
      pytest
      rich
    ]
  );
  postgres = pkgs.postgresql.withPackages (p: [
    p.pgvector
    p.postgis
  ]);
  dotnet = pkgs.dotnetCorePackages.combinePackages [
    pkgs.dotnet-sdk_10
    pkgs.dotnet-sdk_8
  ];

  runtimeAliases =
    pkgs.runCommand "sandbox-runtime-aliases" { nativeBuildInputs = [ pkgs.makeWrapper ]; }
      ''
        mkdir -p $out/bin
        ln -s ${pkgs.nodejs_22}/bin/node $out/bin/node22
        makeWrapper ${pkgs.nodejs_22}/bin/npm $out/bin/npm22 --prefix PATH : ${pkgs.nodejs_22}/bin
        makeWrapper ${pkgs.nodejs_22}/bin/npx $out/bin/npx22 --prefix PATH : ${pkgs.nodejs_22}/bin
        ln -s ${pkgs.nodejs_24}/bin/node $out/bin/node24
        makeWrapper ${pkgs.nodejs_24}/bin/npm $out/bin/npm24 --prefix PATH : ${pkgs.nodejs_24}/bin
        makeWrapper ${pkgs.nodejs_24}/bin/npx $out/bin/npx24 --prefix PATH : ${pkgs.nodejs_24}/bin
        ln -s ${pkgs.yarn-berry}/bin/yarn $out/bin/yarn-berry
        ln -s ${pkgs.goose}/bin/goose $out/bin/goose-migrate
      '';

  languageAlternatives = map lowPrio (
    with pkgs;
    [
      python311
      python312
      python314
      pypy3
      nodejs_22
      nodejs_24
      yarn-berry
      jdk17
      jdk25
      gfortran
      goose
    ]
  );

  languages = with pkgs; [
    beamPackages.elixir
    bun
    deno
    dotnet
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
    python
    ruby
    typescript
    uv
    yarn
    zig
    groovy
    beamPackages.erlang
    rebar3
    gleam
    ghc
    cabal-install
    stack
    ocaml
    dune_3
    opam
    racket
    scala-cli
    sbt
    clojure
    leiningen
    babashka
    nim
    crystal
    odin
    swift
    sbcl
    julia
    R
    octave
    dart
    luajit
    luarocks
    solc
    foundry
    wasmtime
    wasmer
    wabt
    binaryen
    emscripten
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
    pkgs.cargo-nextest
    pkgs.cargo-watch
    pkgs.bacon
    pkgs.cargo-expand
    pkgs.cargo-machete
    pkgs.cargo-llvm-cov
    pkgs.cargo-flamegraph
    pkgs.cargo-insta
    pkgs.cargo-hack
    pkgs.cargo-semver-checks
    pkgs.cargo-zigbuild
    pkgs.cargo-bloat
    pkgs.cargo-show-asm
    pkgs.sqlx-cli
    pkgs.diesel-cli
    pkgs.wasm-pack
    pkgs.trunk
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
    pkgs.mold
    pkgs.lld
    pkgs.ccache
    pkgs.sccache
    pkgs.bazel_7
    pkgs.go-task
    pkgs.scons
    pkgs.bear
    pkgs.cppcheck
    pkgs.include-what-you-use
    pkgs.nasm
    pkgs.bison
    pkgs.flex
    pkgs.doxygen
    pkgs.gersemi
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
    csharp-ls
    tinymist
    fsautocomplete
    haskell-language-server
    ocamlPackages.ocaml-lsp
    metals
    clojure-lsp
    astro-language-server
    emmet-language-server
    prisma-language-server
    vtsls
    helm-ls
    docker-compose-language-service
    protols
    starpls
    neocmakelsp
    mesonlsp
    texlab
    typos-lsp
    harper
    perlnavigator
    fish-lsp
    just-lsp
    postgres-language-server
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
    phpstan
    clj-kondo
    ktlint
    detekt
    checkstyle
    squawk
    shellharden
    bats
    vale
    lychee
    editorconfig-checker
    reuse
    zizmor
    checkov
    conftest
    open-policy-agent
    regal
    kube-linter
  ];

  formatters = with pkgs; [
    gofumpt
    google-java-format
    ktfmt
    nixfmt
    prettier
    shfmt
    stylua
    csharpier
    phpPackages.php-cs-fixer
    ormolu
    fourmolu
    ocamlformat
    cljfmt
    scalafmt
    swift-format
    pgformatter
    sql-formatter
    sqruff
    yamlfmt
    html-tidy
    djlint
    bazel-buildtools
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

  # The desktop supplies Chromium and Firefox; mermaid-cli also uses Chromium.
  networkAndWeb = with pkgs; [
    aria2
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
    oha
    k6
    vegeta
    wrk
    ghz
    doggo
    gping
    trippy
    iperf3
    wireshark-cli
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
    postgres
    valkey
    memcached
    rabbitmq-server
    apacheKafka
    mosquitto
    opensearch
    meilisearch
    typesense
    qdrant
    clickhouse
    influxdb2
    neo4j
    surrealdb
    ferretdb
    prometheus
    opentelemetry-collector
    keycloak
    haproxy
    envoy
    traefik
    pgbouncer
    mongodb-ce
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
    heaptrack
    bcc
    uftrace
    elfutils
    kcov
    lcov
    gcovr
    bloaty
    inferno
    rizin
    binwalk
    checksec
    diffoscope
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
    pkgs.ncurses
    pkgs.gettext
    pkgs.inetutils
    pkgs.nettools
    pkgs.whois
    pkgs.rename
    pkgs.dos2unix
    pkgs.lz4
    pkgs.brotli
    pkgs.cpio
    pkgs.cabextract
    pkgs.dpkg
    pkgs.rpm
    pkgs.inotify-tools
    pkgs.sysstat
    pkgs.patchelf
    pkgs.zsh
    pkgs.fish
    pkgs.nushell
    pkgs.bash-completion
    pkgs.neovim
    pkgs.helix
    pkgs.nano
    pkgs.micro
    pkgs.kakoune
    pkgs.emacs-nox
    pkgs.zellij
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
    sandbox-desktop
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
    pulumi-bin
    ansible
    kubectx
    stern
    helmfile
    kubeseal
    argocd
    fluxcd
    eksctl
    istioctl
    cilium-cli
    hcloud
    oci-cli
    linode-cli
    scaleway-cli
    s5cmd
    minio-client
    regclient
    azure-storage-azcopy
    supabase-cli
    stripe-cli
    netlify-cli
    firebase-tools
    railway
    heroku
    turso-cli
    pscale
    natscli
    kcat
    redpanda-client
    temporal-cli
    atlas
    dbmate
    terraform
    packer
    vault
    consul
    nomad
  ];
  mcp = with pkgs; [
    github-mcp-server
    playwright-mcp
    mcp-nixos
    mcp-grafana
    mcp-proxy
  ];
  humanTools = with pkgs; [
    eza
    zoxide
    starship
    atuin
    carapace
    lazygit
    gitui
    gitu
    tig
    lazyjj
    jjui
    serie
    yazi
    broot
    glow
    moor
    erdtree
    bottom
    btop
    procs
    viddy
    hwatch
    dust
    duf
    dysk
    lnav
    tailspin
    hl-log-viewer
    csvlens
    tabiew
    visidata
    jnv
    posting
    scooter
    serpl
  ];
  searchAndProcess = with pkgs; [
    ripgrep-all
    choose
    grex
    jaq
    xan
    csvkit
    yj
    jc
    cue
    go-jsonnet
    pkl
    ouch
    xcp
    rip2
    fclones
    kondo
    pueue
    mprocs
    process-compose
    universal-ctags
    tree-sitter
    global
    cscope
  ];
  gitAndForges = with pkgs; [
    mergiraf
    git-absorb
    git-branchless
    git-cliff
    git-filter-repo
    git-sizer
    glab
    tea
    hut
    mercurial
    subversion
    prek
    lefthook
  ];
  goTools = with pkgs; [
    gotools
    go-tools
    govulncheck
    gotestsum
    air
    templ
    sqlc
    mockgen
    golines
    goreleaser
    ko
    oapi-codegen
    protoc-gen-go
    protoc-gen-go-grpc
    protoc-gen-connect-go
  ];
  pythonTools = with pkgs; [
    ty
    pyrefly
    poetry
    pdm
    hatch
    pipx
    bandit
    pip-audit
    memray
  ];
  javascriptTools = with pkgs; [
    oxlint
    dprint
    stylelint
    prisma-engines
    playwright-driver.browsers
    chromedriver
    geckodriver
  ];
  security = with pkgs; [
    trufflehog
    grype
    ssh-audit
    testssl
    sslscan
    minisign
    rage
    jwt-cli
    openbao
    cfssl
    slsa-verifier
    _1password-cli
    codeql
  ];
  databaseClients = with pkgs; [
    usql
    pgcli
    litecli
    mycli
    harlequin
    lazysql
    rainfrog
  ];
  docsAndMedia = with pkgs; [
    d2
    plantuml
    mdbook
    zola
    hugo
    asciidoctor
    texliveMedium
    librsvg
    oxipng
    pngquant
    jpegoptim
    libwebp
    libavif
    vips
    gifsicle
    gifski
    sox
    ocrmypdf
    mupdf
    python3Packages.weasyprint
    libreoffice-stable
    vhs
    charm-freeze
    asciinema
    asciinema-agg
    gum
    yt-dlp
  ];
in
lib.concatLists [
  docsAndMedia
  databaseClients
  security
  javascriptTools
  pythonTools
  goTools
  gitAndForges
  searchAndProcess
  humanTools
  mcp
  agents
  checkers
  cloud
  dataAndText
  debugAndProfile
  formatters
  languages
  languageAlternatives
  [ runtimeAliases ]
  native
  networkAndWeb
  runtime
  rust
  servers
  services
  shell
]
