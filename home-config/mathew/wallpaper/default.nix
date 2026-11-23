# Random wallpaper on login and the colour palette that follows it. How it works: docs/hyprland.md.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  scriptPath = ".local/bin/set-random-wallpaper.sh";
  common = import ./common.nix { inherit config; };
  inherit (common) findImages paletteDir;
  palette = import ./palettes.nix { inherit lib pkgs common; };
  inherit (palette) palettes defaultWallpaper;
  location = import ../location.nix;
  # sunwait takes the hemisphere as a letter.
  coordinate =
    pos: neg: v:
    if v >= 0 then "${toString v}${pos}" else "${toString (-v)}${neg}";

  # The light or dark mode: the palette of the wallpaper, the GTK settings and the reload of the consumers; the daemon
  # follows the sun (the Waybar module and the service below call it).
  themeMode = pkgs.writeShellApplication {
    name = "theme-mode";
    runtimeInputs = with pkgs; [
      coreutils
      dconf
      jq
      mako
      procps
      sunwait
      systemd
    ];
    runtimeEnv = {
      THEME_PALETTES = "${palettes}";
      THEME_STATE = paletteDir;
      THEME_DEFAULT_WALLPAPER = defaultWallpaper;
      THEME_LAT = coordinate "N" "S" location.latitude;
      THEME_LON = coordinate "E" "W" location.longitude;
      # Paper has a monochrome variant for a dark background only.
      THEME_ICONS_DARK = "Paper-Mono-Dark";
      THEME_ICONS_LIGHT = "Paper";
    };
    text = builtins.readFile ./theme-mode.sh;
  };
in
{
  home = {
    packages = [ themeMode ];

    file."${scriptPath}" = {
      executable = true;
      text = ''
        #!/usr/bin/env sh
        RANDOM_WALL=$(${findImages} | shuf -n 1)
        DIR=${paletteDir}
        mkdir -p "$DIR"
        # The palette of this wallpaper, so that theme-mode and a later switch take the files from the same palette.
        basename "$RANDOM_WALL" > "$DIR/wallpaper"
        ${themeMode}/bin/theme-mode apply
        # hyprlock reads this link, not a screenshot: a screenshot taken before the first wallpaper would be empty.
        ln -sf "$RANDOM_WALL" "$DIR/lock-background.new"
        mv -f -T "$DIR/lock-background.new" "$DIR/lock-background"
        exec hyprctl hyprpaper wallpaper ,"$RANDOM_WALL"
      '';
    };

    # Every switch refreshes the files from the palette of the current wallpaper and mode (new templates and colour
    # roles reach the state directory), or from the default wallpaper before the script ever ran.
    activation.seedWallpaperPalette = lib.hm.dag.entryAfter [ "writeBoundary" "dconfSettings" ] ''
      name=$(cat ${paletteDir}/wallpaper 2>/dev/null || true)
      run mkdir -p ${paletteDir}
      # The link targets a store path that a later garbage collection can remove, so it is renewed on every switch.
      img=${common.wallDir}/"$name"
      [ -n "$name" ] && [ -e "$img" ] || img=${common.wallDir}/${defaultWallpaper}
      run ln -sfn "$img" ${paletteDir}/lock-background
      run ${themeMode}/bin/theme-mode apply
    '';
  };

  # The mode follows the sun like the night colour (wlsunset.nix). The first application is a pre-start step, so that
  # waybar, ordered after it, starts in the right mode.
  systemd.user.services.theme-mode = {
    Unit = {
      Description = "Light or dark theme by the sun";
      After = [ "random-wallpaper.service" ];
      Before = [ "waybar.service" ];
    };
    Service = {
      ExecStartPre = "${themeMode}/bin/theme-mode auto";
      ExecStart = "${themeMode}/bin/theme-mode daemon";
      Restart = "on-failure";
      RestartSec = 10;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  systemd.user.services.random-wallpaper = {
    Unit = {
      Description = "Set random wallpaper on login";
      After = [
        "hyprpaper.service"
        "graphical-session.target"
      ];
      # The script reloads waybar; a waybar that is still starting dies on SIGUSR2.
      Before = [ "waybar.service" ];
      # hyprctl needs a running Hyprland; skip quietly in any other session instead of failing.
      ConditionEnvironment = "HYPRLAND_INSTANCE_SIGNATURE";
      # A hyprpaper restart after login is not covered by the ordering; retry a few times, spaced.
      StartLimitIntervalSec = 60;
      StartLimitBurst = 5;
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${config.home.homeDirectory}/${scriptPath}";
      Restart = "on-failure";
      RestartSec = 2;
    };
    Install = {
      WantedBy = [
        "graphical-session.target"
        "hyprpaper.service"
      ];
    };
  };
}
