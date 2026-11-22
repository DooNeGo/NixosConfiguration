{ pkgs, ... }: {
  environment.etc."sddm/hyprland.lua".source = ./sddm-hyprland.lua;

  environment.systemPackages = with pkgs; [
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
      settings.Wayland.CompositorCommand = "start-hyprland -- -c /etc/sddm/hyprland.lua";
      theme = "catppuccin-mocha-mauve";
    };
  };
}
