{ pkgs, ... }: {
  services.xserver.videoDrivers = [ "nvidia" ];

  #boot = {
  #  initrd.kernelModules = [ "nvidia" ];
  #  extraModulePackages = [ config.boot.kernelPackages.nvidia_x11 ];
  #};

  environment.systemPackages = with pkgs; [
    nvtopPackages.nvidia
    nvidia_oc
  ];

  hardware = {
    graphics = {
      enable = true;
      enable32Bit = true;
    };

    nvidia = {
      modesetting.enable = true;
      powerManagement.enable = true;
      open = true;
      #package = pkgs.linuxPackages_latest.nvidia_x11;
    };
  };

#   systemd.services.nvidia_oc = {
#     enabled = true;
#     description = "NVIDIA Overclocking Service";
#     after = [ "network.target" ];
#     wantedBy = [ "multi-user.target" ];
#     serviceConfig = {
#       ExecStart = ''nvidia_oc set --index 0 --power-limit  --mem-offset 200'';
#     };
#   };
}
