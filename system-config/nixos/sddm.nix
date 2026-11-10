{ pkgs, ... }: {
  environment.systemPackages = with pkgs; [
    weston
    (pkgs.catppuccin-sddm.override {
      flavor = "mocha";
      accent = "mauve";
    })
  ];

  services.displayManager = {
    # The session must be the UWSM one: HM session vars (NVIDIA env etc.) reach the compositor only via ~/.config/uwsm/env.
    defaultSession = "hyprland-uwsm";

    sddm = {
      enable = true;
      wayland.enable = true;
      settings.Wayland.CompositorCommand = "start-hyprland";
      theme = "catppuccin-mocha-mauve";
    };
  };
}
