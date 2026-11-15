{ pkgs, ... }: {
  fonts.packages = with pkgs; [
    noto-fonts
    font-awesome
    nerd-fonts.jetbrains-mono
  ];

  security.polkit.enable = true;

  programs = {
    hyprland = {
      enable = true;
      withUWSM = true;
    };
  };
}
