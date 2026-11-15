# Values the palette build, the wallpaper script and the activation step share.
{
  config,
  pkgs,
}:
rec {
  wallDir = ../../../assets/wallpapers;
  paletteDir = "${config.home.homeDirectory}/.local/state/wallpaper-palette";

  # Only the top level and only images: any other file in the directory would break the palette build and the pick.
  findImages = "find ${wallDir} -maxdepth 1 -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \\)";

  # Tell every running consumer of this user to read the new palette files; none of them is required to run.
  # `prefix` is `run ` in the activation step, so that a dry run prints the commands instead of executing them.
  reloadConsumers = prefix: ''
    ${prefix}${pkgs.systemd}/bin/systemctl --user try-reload-or-restart waybar.service || true
    ${prefix}${pkgs.mako}/bin/makoctl reload || true
    # The Nix kitty runs as a wrapped process named .kitty-wrapped.
    ${prefix}${pkgs.procps}/bin/pkill -U "$(id -u)" -USR1 -x '\.kitty-wrapped|kitty' || true
  '';
}
