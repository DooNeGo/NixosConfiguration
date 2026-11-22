# GTK: the theme `matugen-glass` is adw-gtk3-dark with the shapes of the desktop (gtk/theme.css) on top, and the
# colours come from the wallpaper palette through the user gtk.css of GTK 3 and GTK 4 (libadwaita ignores the theme
# but reads that file too). How the palette is made and reloaded: docs/hyprland.md.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  style = import ./style lib;
  adw = "${pkgs.adw-gtk3}/share/themes/adw-gtk3-dark";
  palette = "file://${config.home.homeDirectory}/.local/state/wallpaper-palette/gtk.css";
  shapes = style.subst (builtins.readFile ./gtk/theme.css);

  theme = pkgs.runCommand "matugen-glass-theme" { } ''
    dir=$out/share/themes/matugen-glass
    mkdir -p $dir/gtk-3.0 $dir/gtk-4.0
    printf '%s\n' '[Desktop Entry]' 'Type=X-GNOME-Metatheme' 'Name=matugen-glass' \
      'Comment=adw-gtk3-dark in the colours of the wallpaper' '[X-GNOME-Metatheme]' \
      'GtkTheme=matugen-glass' 'IconTheme=${config.gtk.iconTheme.name}' > $dir/index.theme
    for v in 3.0 4.0; do
      printf '@import url("file://${adw}/gtk-%s/gtk.css");\n' "$v" > $dir/gtk-$v/gtk.css
      cat ${pkgs.writeText "matugen-glass.css" shapes} >> $dir/gtk-$v/gtk.css
    done
  '';
in
{
  gtk = {
    enable = true;
    colorScheme = "dark";

    theme = {
      name = "matugen-glass";
      package = theme;
    };

    iconTheme = {
      package = pkgs.paper-icon-theme;
      name = "Paper-Mono-Dark";
    };

    font = {
      name = style.fontFamily;
      size = 11;
    };

    gtk3.extraCss = ''@import url("${palette}");'';
    gtk4.extraCss = ''@import url("${palette}");'';
  };
}
