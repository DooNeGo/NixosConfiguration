{ pkgs, config, ... }: {
  services.xserver.videoDrivers = [ "nvidia" ];

  environment.systemPackages = with pkgs; [
    nvtopPackages.nvidia
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
      #branch = "bleeding_edge";
      #package = config.boot.kernelPackages.nvidiaPackages.beta;
    };
  };

  systemd.services.nvidia-target-temperature = {
    enable = true;
    description = "Setting NVIDIA target temperature";
    after = [ "network.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${config.boot.kernelPackages.nvidia_x11.bin}/bin/nvidia-smi -gtt 67";
      RemainAfterExit = true;
    };
    wantedBy = [ "multi-user.target" ];
  };
}
