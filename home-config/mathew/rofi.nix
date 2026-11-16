{
  config,
  lib,
  pkgs,
  ...
}:
let
  style = import ./style lib;
  theme = pkgs.writeText "rofi-glass.rasi" (style.subst (builtins.readFile ./rofi-glass.rasi));
  clipboardPick = pkgs.writeShellApplication {
    name = "clipboard-pick";
    runtimeInputs = with pkgs; [
      cliphist
      imagemagick
      jq
      rofi
      wl-clipboard
      wtype
    ];
    text = builtins.readFile ./clipboard-pick.sh;
  };
in
{
  home.packages = [ clipboardPick ];

  # The launcher (SUPER+E) and the clipboard history (SUPER+V). The colours come from the wallpaper palette.
  programs.rofi = {
    enable = true;
    theme = "${theme}";
    settings = {
      terminal = "kitty";
      show-icons = true;
      icon-theme = config.gtk.iconTheme.name;
      display-drun = "󰀻";
      drun-display-format = "{name}";
    };
  };
}
