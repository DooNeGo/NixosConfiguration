# Yazi, the terminal file manager (Super+R). Its colours are the ANSI palette of kitty, which follows the wallpaper
# (docs/hyprland.md), so it has no palette file of its own. Nemo (nemo.nix) stays for drag and drop.
{ pkgs, ... }:
let
  # Glow's style with ANSI colour numbers only, so the rendered Markdown follows the wallpaper like the rest of Yazi.
  glowStyle = pkgs.writeText "glow-style.json" (
    builtins.toJSON {
      document.margin = 0;
      heading = {
        bold = true;
        color = "4";
      };
      h1 = {
        prefix = "█ ";
        color = "4";
      };
      h2.prefix = "▌ ";
      h3.prefix = "▎ ";
      strong.bold = true;
      emph.italic = true;
      code = {
        color = "3";
        background_color = "0";
      };
      code_block.margin = 1;
      link = {
        color = "6";
        underline = true;
      };
      link_text = {
        color = "6";
        bold = true;
      };
      block_quote = {
        color = "8";
        indent = 1;
        indent_token = "│ ";
      };
      item.block_prefix = "• ";
      enumeration.block_prefix = ". ";
      hr = {
        color = "8";
        format = "────────";
      };
    }
  );
in
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
          run = ''piper -- CLICOLOR_FORCE=1 glow -s ${glowStyle} -w=$w "$1"'';
        }
      ];
      preview = {
        max_width = 1600;
        max_height = 1200;
      };
    };
  };
}
