{ config, pkgs, ... }:
let
  scriptPath = ".local/bin/set-random-wallpaper.sh";
  wallDir = ../../assets/wallpapers;
  # Only images: any other file in the directory would break the palette build and the random pick.
  findImages = "find ${wallDir} -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \\)";

  # One palette file per wallpaper, named after it; --source-color-index picks the colour without asking on a terminal.
  palettes = pkgs.runCommand "wallpaper-palettes" { nativeBuildInputs = [ pkgs.matugen ]; } ''
    export HOME=$TMPDIR
    mkdir -p $out
    ${findImages} | while read -r img; do
      name=$(basename "$img")
      printf '[config]\n[templates.waybar]\ninput_path = "%s"\noutput_path = "%s"\n' \
        ${./waybar-colors.tmpl.css} "$out/$name.css" > "$TMPDIR/matugen.toml"
      matugen -q -c "$TMPDIR/matugen.toml" -m dark -t scheme-tonal-spot --source-color-index 0 image "$img"
    done
  '';
in
{
  home.file."${scriptPath}" = {
    executable = true;
    text = ''
      #!/usr/bin/env sh
      RANDOM_WALL=$(${findImages} | shuf -n 1)
      # Same file the bar imports (waybar.nix); rename keeps the bar from reading a half-written file.
      COLORS="''${XDG_STATE_HOME:-$HOME/.local/state}/waybar/colors.css"
      mkdir -p "$(dirname "$COLORS")"
      cp ${palettes}/"$(basename "$RANDOM_WALL")".css "$COLORS.new"
      mv "$COLORS.new" "$COLORS"
      ${pkgs.systemd}/bin/systemctl --user try-reload-or-restart waybar.service || true
      exec hyprctl hyprpaper wallpaper ,"$RANDOM_WALL"
    '';
  };

  systemd.user.services.random-wallpaper = {
    Unit = {
      Description = "Set random wallpaper on login";
      After = [
        "hyprpaper.service"
        "graphical-session.target"
      ];
      # hyprctl needs a running Hyprland; skip quietly in any other session instead of failing.
      ConditionEnvironment = "HYPRLAND_INSTANCE_SIGNATURE";
      # hyprpaper may not listen on its socket yet right after start: a few spaced retries, not a burst.
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
