# GTK: the themes `matugen-glass-dark` and `matugen-glass-light` are adw-gtk3-dark and adw-gtk3 with the shapes of the
# desktop (gtk/theme.css) on top, and the colours come from the wallpaper palette through the user gtk.css of GTK 3 and
# GTK 4 (libadwaita ignores the theme but reads that file too). `theme-mode` (wallpaper/) switches the theme name and
# the colour scheme in dconf, so open Nemo and Chrome change at once. How the palette is made and reloaded:
# docs/hyprland.md.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  style = import ./style lib;
  palette = "file://${config.home.homeDirectory}/.local/state/wallpaper-palette/gtk.css";
  shapes = pkgs.writeText "matugen-glass.css" (style.subst (builtins.readFile ./gtk/theme.css));
  # The base theme of each variant.
  bases = {
    dark = "adw-gtk3-dark";
    light = "adw-gtk3";
  };

  theme = pkgs.runCommand "matugen-glass-theme" { } ''
    ${lib.concatStrings (
      lib.mapAttrsToList (variant: base: ''
        dir=$out/share/themes/matugen-glass-${variant}
        mkdir -p $dir/gtk-3.0 $dir/gtk-4.0
        printf '%s\n' '[Desktop Entry]' 'Type=X-GNOME-Metatheme' 'Name=matugen-glass-${variant}' \
          'Comment=${base} in the colours of the wallpaper' '[X-GNOME-Metatheme]' \
          'GtkTheme=matugen-glass-${variant}' 'IconTheme=${config.gtk.iconTheme.name}' > $dir/index.theme
        for v in 3.0 4.0; do
          printf '@import url("file://${pkgs.adw-gtk3}/share/themes/${base}/gtk-%s/gtk.css");\n' "$v" > $dir/gtk-$v/gtk.css
          cat ${shapes} >> $dir/gtk-$v/gtk.css
        done
      '') bases
    )}
  '';
in
{
  gtk = {
    enable = true;
    colorScheme = "dark";

    # The dark theme is the one of a session that has no mode yet; `theme-mode` sets the real one.
    theme = {
      name = "matugen-glass-dark";
      package = theme;
    };

    iconTheme = {
      package = pkgs.paper-icon-theme;
      name = "Paper-Mono-Dark";
    };

    # Every GTK application takes this font, Chrome's interface included: a proportional one. Nemo gets the
    # desktop font from gtk/theme.css.
    font = {
      name = "Sans";
      size = 11;
    };

    gtk3.extraCss = ''@import url("${palette}");'';
    gtk4.extraCss = ''@import url("${palette}");'';
  };
}
