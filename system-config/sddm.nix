{ pkgs, ... }: {
  environment.systemPackages = with pkgs; [
    weston
  ]; 

  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
    theme = "maldives";
  };
}
