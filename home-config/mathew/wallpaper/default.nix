# Random wallpaper on login and the colour palette that follows it. How it works: docs/hyprland.md.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  scriptPath = ".local/bin/set-random-wallpaper.sh";
  common = import ./common.nix { inherit config pkgs; };
  inherit (common) findImages paletteDir reloadConsumers;
  palette = import ./palettes.nix { inherit lib pkgs common; };
  inherit (palette) palettes defaultWallpaper;
in
{
  home.file."${scriptPath}" = {
    executable = true;
    text = ''
      #!/usr/bin/env sh
      RANDOM_WALL=$(${findImages} | shuf -n 1)
      # Rename keeps a consumer from reading a half-written file.
      DIR=${paletteDir}
      mkdir -p "$DIR"
      for f in ${lib.concatStringsSep " " palette.files}; do
        cp --no-preserve=mode ${palettes}/"$(basename "$RANDOM_WALL")"/"$f" "$DIR/$f.new"
        mv -f "$DIR/$f.new" "$DIR/$f"
      done
      ${reloadConsumers ""}
      # The palette of this wallpaper, so that a later switch refreshes the files from the same palette.
      basename "$RANDOM_WALL" > "$DIR/wallpaper"
      # hyprlock reads this link, not a screenshot: a screenshot taken before the first wallpaper would be empty.
      ln -sf "$RANDOM_WALL" "$DIR/lock-background.new"
      mv -f -T "$DIR/lock-background.new" "$DIR/lock-background"
      exec hyprctl hyprpaper wallpaper ,"$RANDOM_WALL"
    '';
  };

  # Every switch refreshes the files from the palette of the current wallpaper (new templates and colour roles
  # reach the state directory), or from the default one before the script ever ran.
  home.activation.seedWallpaperPalette = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    name=$(cat ${paletteDir}/wallpaper 2>/dev/null || true)
    src=${palettes}/"$name"
    [ -n "$name" ] && [ -d "$src" ] || src=${palettes}/${defaultWallpaper}
    run mkdir -p ${paletteDir}
    run cp -f --no-preserve=mode "$src"/* ${paletteDir}/
    # The link targets a store path that a later garbage collection can remove, so it is renewed on every switch.
    img=${common.wallDir}/"$name"
    [ -n "$name" ] && [ -e "$img" ] || img=${common.wallDir}/${defaultWallpaper}
    run ln -sfn "$img" ${paletteDir}/lock-background
    if [ -S "''${XDG_RUNTIME_DIR:-/nonexistent}/bus" ]; then
      ${reloadConsumers "run "}
    else
      echo "No user session: waybar, mako and kitty read the palette when they next start."
    fi
  '';

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
