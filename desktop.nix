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
  alsaConfig = pkgs.writeText "sandbox-desktop-alsa.conf" ''
    # Use this session's Pulse server even when the host defaults to PipeWire.
    pcm.!default { type pulse }
    ctl.!default { type pulse }
  '';
  pulseClientConfig = pkgs.writeText "sandbox-desktop-pulse.conf" ''
    autospawn = no
    enable-shm = no
  '';
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
      selkies
      pulseaudio
      nixgl.nixGLMesa
      xorg-server
      xf86-video-dummy
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
    export GALLIUM_DRIVER=llvmpipe
    # Headless GLX lacks sRGB visuals; SDL's EGL path supports those contexts.
    export SDL_VIDEO_FORCE_EGL=1
    export VK_DRIVER_FILES=${pkgs.mesa}/share/vulkan/icd.d/lvp_icd.x86_64.json
    export ALSA_CONFIG_PATH=${alsaConfig}
    export ALSA_PLUGIN_DIR=${pkgs.alsa-plugins}/lib/alsa-lib
    export PULSE_CLIENTCONFIG=${pulseClientConfig}
    export GDK_BACKEND=x11
    export QT_QPA_PLATFORM=xcb
    export MOZ_ENABLE_WAYLAND=0
    export XDG_SESSION_TYPE=x11
    export XDG_CURRENT_DESKTOP=XFCE
    unset WAYLAND_DISPLAY SESSION_MANAGER DBUS_SESSION_BUS_ADDRESS
  '';

  # SSH supplies authentication and encryption for the loopback-only web server.
  # xinit owns this process group, including audio and D-Bus-activated services.
  session = pkgs.writeShellApplication {
    name = "sandbox-desktop-session";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      children=()
      cleanup() {
        # xinit gives its client a separate process group. D-Bus activation
        # reparents services, so stopping just the direct children leaks
        # their daemons. Stop the whole client group, including those services.
        trap "" HUP INT TERM
        kill -TERM -- "-$$" 2>/dev/null || true
        wait "''${children[@]}" 2>/dev/null || true
      }
      trap cleanup EXIT
      trap 'exit 129' HUP
      trap 'exit 130' INT
      trap 'exit 143' TERM
      ${pkgs.pulseaudio}/bin/pulseaudio --daemonize=no --exit-idle-time=-1 \
        --disable-shm=yes --log-target=stderr -n \
        --load="module-native-protocol-unix socket=$XDG_RUNTIME_DIR/pulse/native" \
        --load='module-null-sink sink_name=output sink_properties=device.description=Desktop' &
      audio=$!
      children+=("$audio")
      ready=false
      for ((attempt=0; attempt<50; attempt++)); do
        if ${pkgs.pulseaudio}/bin/pactl info >/dev/null 2>&1; then
          ready=true
          break
        fi
        kill -0 "$audio" 2>/dev/null || break
        sleep 0.1
      done
      if [[ $ready != true ]]; then
        echo 'Desktop audio did not become ready.' >&2
        exit 1
      fi
      ${pkgs.pulseaudio}/bin/pactl set-default-sink output
      ${pkgs.selkies}/bin/selkies --addr=127.0.0.1 --port="$SANDBOX_DESKTOP_PORT" \
        --enable-https=false --enable-basic-auth=false \
        --mode=websockets --enable-dual-mode=false \
        --encoder=h264enc --use-cpu=true --framerate=30 \
        --gamepad-enabled=false --webcam-enabled=false \
        --audio-device-name=output.monitor &
      children+=("$!")
      ${pkgs.dbus}/bin/dbus-run-session \
        --config-file=${pkgs.dbus}/share/dbus-1/session.conf \
        -- ${pkgs.xfce4-session}/bin/xfce4-session &
      children+=("$!")
      printf '\nDesktop: http://127.0.0.1:%s/\n' "$SANDBOX_DESKTOP_PORT"
      printf 'From your computer: ssh -N -L %s:127.0.0.1:%s <sandbox-ssh-alias>\n\n' "$SANDBOX_DESKTOP_PORT" "$SANDBOX_DESKTOP_PORT"
      wait -n "''${children[@]}"
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
      Open http://127.0.0.1:6080/
      For a remote sandbox, first forward the port through its SSH connection:
        ssh -N -L 6080:127.0.0.1:6080 <sandbox-ssh-alias>

      Run chromium or firefox from the desktop terminal, or use Applications.
      Graphics render on the CPU; sound streams to the browser. Enable Gaming
      mode in the browser for relative mouse input. Escape releases the pointer.
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
      export XDG_RUNTIME_DIR="$runtime"
      export XAUTHORITY="$runtime/Xauthority"
      export PULSE_SERVER="unix:$runtime/pulse/native"
      mkdir -p "$runtime/pulse" "$runtime/xorg.conf.d"
      touch "$XAUTHORITY"
      ${pkgs.xauth}/bin/xauth -f "$XAUTHORITY" add "$display" . "$(mcookie)"
      # The dummy driver supplies RandR resizing without a GPU or physical VT.
      # Use our module paths and config, independent of the host's Xorg setup.
      modeline=$(${pkgs.libxcvt}/bin/cvt "''${geometry%x*}" "''${geometry#*x}" 60 \
        | ${pkgs.gnused}/bin/sed -n 's/^Modeline "[^"]*"/Modeline "sandbox"/p')
      cat > "$runtime/xorg.conf" <<XORG
      Section "ServerFlags"
        Option "AutoAddDevices" "false"
        Option "AutoEnableDevices" "false"
        Option "AutoAddGPU" "false"
        Option "DontVTSwitch" "true"
      EndSection
      Section "Device"
        Identifier "headless"
        Driver "dummy"
        VideoRam 256000
      EndSection
      Section "Monitor"
        Identifier "monitor"
        HorizSync 5.0-1000.0
        VertRefresh 5.0-200.0
        $modeline
      EndSection
      Section "Screen"
        Identifier "screen"
        Device "headless"
        Monitor "monitor"
        DefaultDepth 24
        SubSection "Display"
          Depth 24
          Modes "sandbox"
        EndSubSection
      EndSection
      XORG
      ${pkgs.nixgl.nixGLMesa}/bin/nixGLMesa \
        ${pkgs.xinit}/bin/xinit ${session}/bin/sandbox-desktop-session -- \
        ${pkgs.xorg-server}/bin/Xorg "$display" \
        -auth "$XAUTHORITY" -nolisten tcp -noreset -novtswitch -sharevts \
        -config "$runtime/xorg.conf" -configdir "$runtime/xorg.conf.d" \
        -modulepath ${pkgs.xf86-video-dummy}/lib/xorg/modules,${pkgs.xorg-server}/lib/xorg/modules \
        -logfile "$runtime/Xorg.log" -s 0 &
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
