# Yazi, the terminal file manager (Super+R). Nemo (nemo.nix) stays for drag and drop.
{ config, pkgs, ... }:
let
  inherit (import ./wallpaper/common.nix { inherit config; }) paletteDir;
in
{
  xdg.configFile."yazi/theme.toml".source =
    config.lib.file.mkOutOfStoreSymlink "${paletteDir}/yazi.toml";

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
      glow
    ];

    plugins.piper = pkgs.yaziPlugins.piper;

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
      # Markdown is rendered by glow through the piper plugin, the rest keeps the built-in previews.
      plugin.prepend_previewers = [
        {
          url = "*.md";
          run = ''piper -- CLICOLOR_FORCE=1 glow -s "${paletteDir}/glow.json" -w=$w "$1"'';
        }
      ];
      preview = {
        max_width = 1600;
        max_height = 1200;
      };
    };
  };
}
