# Nemo, the graphical file manager (Super+Shift+R) and the default for folders: drag and drop into a browser or a
# messenger. The look is in gtk.nix (theme matugen-glass).
{ pkgs, ... }:
{
  # nemo-with-extensions brings nemo-fileroller (archives in the context menu); nemo-preview adds the space-bar preview.
  home.packages = [
    (pkgs.nemo-with-extensions.override { extensions = [ pkgs.nemo-preview ]; })
  ];

  dconf.settings = {
    "org/nemo/preferences" = {
      default-folder-viewer = "list-view";
      show-full-path-titles = true;
      sort-directories-first = true;
    };
    "org/nemo/window-state" = {
      start-with-menu-bar = false;
    };
  };
}
