# A desktop that works in the Ubuntu sandbox without a GPU, display manager,
# NixOS modules, or changes to /etc. xinit owns the X server's lifetime and
# Xfce owns the desktop applications.
{ pkgs }:

let
  inherit (pkgs) lib;
  chromium = pkgs.chromium.override { commandLineArgs = "--disable-gpu"; };
  fonts = [
    pkgs.dejavu_fonts
    pkgs.noto-fonts
    pkgs.noto-fonts-color-emoji
  ];
  fontconfig = pkgs.makeFontsConf { fontDirectories = fonts; };
  defaults = pkgs.runCommand "sandbox-desktop-defaults" { } ''
    config="$out/etc/xdg/xfce4/xfconf/xfce-perchannel-xml"
    mkdir -p "$config"
    cat > "$config/xfwm4.xml" <<'XML'
    <?xml version="1.0" encoding="UTF-8"?>
    <channel name="xfwm4" version="1.0">
      <property name="general" type="empty">
        <property name="use_compositing" type="bool" value="false"/>
      </property>
    </channel>
    XML
    # Keep Xfce's session definition, but let the login session own credential
    # agents. Starting a desktop must not replace an existing SSH/GPG agent.
    substitute ${pkgs.xfce4-session}/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-session.xml \
      "$config/xfce4-session.xml" --replace-fail '</channel>' '
      <property name="startup" type="empty">
        <property name="ssh-agent" type="empty">
          <property name="enabled" type="bool" value="false"/>
        </property>
        <property name="gpg-agent" type="empty">
          <property name="enabled" type="bool" value="false"/>
        </property>
      </property>
    </channel>'
  '';
  packages =
    with pkgs;
    [
      chromium
      firefox
      tigervnc
      novnc
      python3Packages.websockify
      dbus
      dconf
      at-spi2-core
      xinit
      xauth
      xrandr
      xdpyinfo
      xset
      xsetroot
      xfce4-session
      xfwm4
      xfce4-panel
      xfdesktop
      xfce4-settings
      xfconf
      xfce4-appfinder
      xfce4-terminal
      xfce4-exo
      thunar
      mousepad
      adwaita-icon-theme
      hicolor-icon-theme
      xfce4-icon-theme
      shared-mime-info
      desktop-file-utils
      xdg-utils
      xdg-user-dirs
    ]
    ++ fonts;

  environment = ''
    export PATH=${lib.makeBinPath packages}:"$PATH"
    export XDG_DATA_DIRS=${lib.makeSearchPath "share" packages}:"''${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
    export XDG_CONFIG_DIRS=${
      lib.makeSearchPath "etc/xdg" ([ defaults ] ++ packages)
    }:"''${XDG_CONFIG_DIRS:-/etc/xdg}"
    export FONTCONFIG_FILE=${fontconfig}
    export LIBGL_ALWAYS_SOFTWARE=1
    export LIBGL_DRIVERS_PATH=${pkgs.mesa}/lib/dri
    export GALLIUM_DRIVER=llvmpipe
    export GDK_BACKEND=x11
    export QT_QPA_PLATFORM=xcb
    export MOZ_ENABLE_WAYLAND=0
    export XDG_SESSION_TYPE=x11
    export XDG_CURRENT_DESKTOP=XFCE
    unset WAYLAND_DISPLAY SESSION_MANAGER DBUS_SESSION_BUS_ADDRESS
  '';

  # The session's web server is loopback-only. SSH supplies authentication and
  # encryption; Xvnc itself is reachable only through a private Unix socket.
  session = pkgs.writeShellApplication {
    name = "sandbox-desktop-session";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      ${pkgs.python3Packages.websockify}/bin/websockify \
        --web ${pkgs.novnc}/share/webapps/novnc \
        --unix-target "$SANDBOX_VNC_SOCKET" \
        "127.0.0.1:$SANDBOX_DESKTOP_PORT" &
      web=$!
      ${pkgs.dbus}/bin/dbus-run-session \
        --config-file=${pkgs.dbus}/share/dbus-1/session.conf \
        -- ${pkgs.xfce4-session}/bin/xfce4-session &
      desktop=$!
      cleanup() {
        # xinit gives its client a separate process group. D-Bus activation
        # reparents services, so stopping just the two direct children leaks
        # their daemons. Stop the whole client group, including those services.
        trap "" HUP INT TERM
        kill -TERM -- "-$$" 2>/dev/null || true
        wait "$web" "$desktop" 2>/dev/null || true
      }
      trap cleanup EXIT
      trap 'exit 129' HUP
      trap 'exit 130' INT
      trap 'exit 143' TERM
      printf '\nDesktop: http://127.0.0.1:%s/vnc.html?autoconnect=1&resize=remote\n' "$SANDBOX_DESKTOP_PORT"
      printf 'From your computer: ssh -N -L %s:127.0.0.1:%s <sandbox-ssh-alias>\n\n' "$SANDBOX_DESKTOP_PORT" "$SANDBOX_DESKTOP_PORT"
      wait -n "$web" "$desktop"
    '';
  };

  launcher = pkgs.writeShellApplication {
    name = "sandbox-desktop";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.util-linux
    ];
    text = ''
      if [[ ''${1:-} == --help ]]; then
        cat <<'HELP'
      Usage: sandbox-desktop

      Start an Xfce desktop with Firefox, Chromium, a terminal and file manager.
      Open http://127.0.0.1:6080/vnc.html?autoconnect=1&resize=remote
      For a remote sandbox, first forward the port through its SSH connection:
        ssh -N -L 6080:127.0.0.1:6080 <sandbox-ssh-alias>

      Run chromium or firefox from the desktop terminal, or use Applications.
      Ctrl-C or Xfce Log Out stops the desktop. Run in tmux to keep it running
      when you disconnect SSH. Browser profiles stay in your normal home.

      Optional environment variables:
        SANDBOX_DISPLAY        X display (default :1)
        SANDBOX_DESKTOP_PORT   Loopback HTTP port (default 6080)
        SANDBOX_DESKTOP_SIZE   Initial resolution (default 1600x1000)
      HELP
        exit 0
      fi
      if [[ $# != 0 ]]; then
        echo 'Usage: sandbox-desktop [--help]' >&2
        exit 2
      fi
      if [[ $EUID == 0 ]]; then
        echo 'Run sandbox-desktop as the sandbox user, so browsers can use their sandbox.' >&2
        exit 1
      fi
      ${environment}
      display=''${SANDBOX_DISPLAY:-:1}
      export SANDBOX_DESKTOP_PORT=''${SANDBOX_DESKTOP_PORT:-6080}
      geometry=''${SANDBOX_DESKTOP_SIZE:-1600x1000}
      if [[ ! $display =~ ^:[0-9]+$ || ! $SANDBOX_DESKTOP_PORT =~ ^[0-9]+$ || ! $geometry =~ ^[0-9]+x[0-9]+$ ]]; then
        echo 'Expected display :N, a numeric port, and resolution WIDTHxHEIGHT.' >&2
        exit 2
      fi
      runtime=$(mktemp -d "''${XDG_RUNTIME_DIR:-/tmp}/sandbox-desktop.XXXXXX")
      export XDG_RUNTIME_DIR="$runtime"
      export XAUTHORITY="$runtime/Xauthority"
      export SANDBOX_VNC_SOCKET="$runtime/vnc.sock"
      touch "$XAUTHORITY"
      ${pkgs.xauth}/bin/xauth -f "$XAUTHORITY" add "$display" . "$(mcookie)"
      child=
      cleanup() {
        if [[ -n $child ]]; then
          kill "$child" 2>/dev/null || true
          wait "$child" 2>/dev/null || true
        fi
        rm -rf "$runtime"
      }
      trap cleanup EXIT
      trap 'exit 129' HUP
      trap 'exit 130' INT
      trap 'exit 143' TERM
      ${pkgs.xinit}/bin/xinit ${session}/bin/sandbox-desktop-session -- \
        ${pkgs.tigervnc}/bin/Xvnc "$display" \
        -auth "$XAUTHORITY" -nolisten tcp \
        -rfbport -1 -rfbunixpath "$SANDBOX_VNC_SOCKET" -rfbunixmode 0600 \
        -SecurityTypes None -AlwaysShared -geometry "$geometry" -depth 24 \
        -desktop 'Tinfoil sandbox' &
      child=$!
      wait "$child"
    '';
  };
in
pkgs.buildEnv {
  name = "sandbox-desktop";
  paths = packages ++ [ launcher ];
  meta.mainProgram = "sandbox-desktop";
}
