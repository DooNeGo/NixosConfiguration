# Yazi, the terminal file manager (Super+R). Its colours are the ANSI palette of kitty, which follows the wallpaper
# (docs/hyprland.md), so it has no palette file of its own. Nemo (nemo.nix) stays for drag and drop.
{ pkgs, ... }:
{
  programs.yazi = {
    enable = true;
    # `y` changes the shell directory to where yazi was left.
    enableZshIntegration = true;
    shellWrapperName = "y";

    # The previews: PDFs, images, archives, video; the finders and the directory jump.
    extraPackages = with pkgs; [
      fd
      fzf
      zoxide
      ripgrep
      poppler-utils
      imagemagick
      p7zip
      ffmpegthumbnailer
      jq
    ];

    settings = {
      mgr = {
        ratio = [
          1
          3
          4
        ];
        sort_by = "natural";
        sort_dir_first = true;
        show_hidden = false;
        show_symlink = true;
      };
      preview = {
        max_width = 1600;
        max_height = 1200;
      };
    };
  };
}
