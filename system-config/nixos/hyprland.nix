{ pkgs, ... }: {
  fonts.packages = with pkgs; [
    noto-fonts
    font-awesome
  ];

  security.polkit.enable = true;

  programs = {
    hyprland = {
      enable = true;
      withUWSM = true;
    };
  };
}
