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
    # Installs hyprlock and its PAM service: Home Manager cannot write /etc/pam.d, and without it hyprlock falls back to su.
    hyprlock.enable = true;
  };
}
