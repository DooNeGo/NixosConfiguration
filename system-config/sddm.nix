{ pkgs, ... }: {
  environment.systemPackages = with pkgs; [
    weston
    (pkgs.catppuccin-sddm.override {
      flavor = "mocha";
      accent = "mauve";
    })
  ];

  services.displayManager = {
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
