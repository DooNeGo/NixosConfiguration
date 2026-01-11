{ lib, ... }: {
  programs.kitty = {
    enable = true;
    enableGitIntegration = true;

    settings = lib.mkAfter {
      background_opacity = 0.65;
      window_padding_width = 5;
      confirm_os_window_close = 0;

#      color0  = "#${p.base00}";
#      color1  = "#${p.base08}";
#      color2  = "#${p.base0B}";
#      color3  = "#${p.base0A}";
#      color4  = "#${p.base0D}";
#      color5  = "#${p.base0E}";
#      color6  = "#${p.base0C}";
#      color7  = "#${p.base05}";
#      color8  = "#${p.base03}";
#      color9  = "#${p.base08}";
#      color10 = "#${p.base0B}";
#      color11 = "#${p.base0A}";
#      color12 = "#${p.base0D}";
#      color13 = "#${p.base0E}";
#      color14 = "#${p.base0C}";
#      color15 = "#${p.base07}";
    };
  };
}
