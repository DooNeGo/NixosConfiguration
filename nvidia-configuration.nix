{ config, lib, pkgs, ... }:

{
  services.xserver.videoDrivers = [ "nvidia" ];

  environment.systemPackages = with pkgs; [
    nvtopPackages.nvidia
  ];

  hardware = {
    graphics.enable = true;

    nvidia = {
      modesettings.enable = true;
      powerManagement.enable = true;
      open = true;
      nvidiaSettings = true;

      powerManagement = {
        enable = true;
        finegrained = true;
      };
    };
  };
}
