{ pkgs, config, lib, ... }: {
  services.xserver.videoDrivers = [ "nvidia" ];

  environment.systemPackages = with pkgs; [
    nvtopPackages.nvidia
  ];

  nix.settings = {
    substituters = [
      "https://cache.nixos-cuda.org"
    ];
    trusted-public-keys = [
      "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
    ];
  };

  nixpkgs.config.cudaSupport = true;

  hardware = {
    graphics = {
      enable = true;
      enable32Bit = true;
    };

    nvidia = {
      modesetting.enable = true;
      powerManagement.enable = true;
      open = true;
      branch = "bleeding_edge";
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
