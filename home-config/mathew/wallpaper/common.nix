# Values the palette build, the wallpaper script and the activation step share.
{ config }:
rec {
  wallDir = ../../../assets/wallpapers;
  paletteDir = "${config.home.homeDirectory}/.local/state/wallpaper-palette";

  # Only the top level and only images: any other file in the directory would break the palette build and the pick.
  findImages = "find ${wallDir} -maxdepth 1 -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \\)";
}
