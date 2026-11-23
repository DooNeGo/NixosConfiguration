# Qt: the Kvantum theme KvMatugen, KvFlat recoloured by the wallpaper palette (wallpaper/palettes.nix). The two files
# of the theme are links into the palette directory, so a new wallpaper reaches the next Qt window without a switch.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  style = import ./style lib;
  # Fonts in qtct's format: family, size, then the fixed Qt font fields. The interface is proportional, as in GTK.
  font = family: ''"${family},11,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"'';
  qtct = {
    Appearance.style = "kvantum";
    Fonts = {
      general = font "Sans";
      fixed = font style.fontFamily;
    };
  };
  paletteDir = "${config.home.homeDirectory}/.local/state/wallpaper-palette";
  link = name: config.lib.file.mkOutOfStoreSymlink "${paletteDir}/${name}";
in
{
  qt = {
    enable = true;
    platformTheme.name = "qtct";
    style = {
      name = "kvantum";
      package = pkgs.kdePackages.qtstyleplugin-kvantum;
    };

    qt5ctSettings = qtct;
    qt6ctSettings = qtct;

    kvantum = {
      enable = true;
      settings.General.theme = "KvMatugen";
    };
  };

  xdg.configFile = {
    "Kvantum/KvMatugen/KvMatugen.kvconfig".source = link "KvMatugen.kvconfig";
    "Kvantum/KvMatugen/KvMatugen.svg".source = link "KvMatugen.svg";
  };
}
