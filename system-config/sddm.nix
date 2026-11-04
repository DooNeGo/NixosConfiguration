{ pkgs, ... }: {
  environment.systemPackages = with pkgs; [
    weston
    (pkgs.catppuccin-sddm.override {
      flavor = "mocha";
      accent = "mauve";
    })
  ];

  services.displayManager = {
    # Autologin must start the UWSM session: HM session vars (NVIDIA env etc.) reach the compositor only via ~/.config/uwsm/env.
    defaultSession = "hyprland-uwsm";

    autoLogin = {
      enable = true;
      user = "mathew";
    };

    sddm = {
      enable = true;
      wayland.enable = true;
      settings.Wayland.CompositorCommand = "start-hyprland";
      theme = "catppuccin-mocha-mauve";
    };
  };
}
