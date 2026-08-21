{ pkgs, config, lib, ... }: {
  services.xserver.videoDrivers = [ "nvidia" ];

  environment.systemPackages = with pkgs; [
    nvtopPackages.nvidia
  ];

  nix.settings = {
    substituters = [
      #"https://cuda-maintainers.cachix.org"
      "https://cache.nixos-cuda.org"
    ];
    trusted-public-keys = [
      #"cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
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
      #branch = "bleeding_edge";
      #package = config.boot.kernelPackages.nvidiaPackages.beta;
      package = config.boot.kernelPackages.nvidiaPackages.mkDriver {
        version = "610.57.04";
          sha256_64bit = "sha256-suk1xmuDuwDAyFe8jg7g/VLekoa0DJzB7sKafOfrEW0=";
          sha256_aarch64 = "sha256-suk1xmuDuwDAyFe8jg7g/VLekggggggB7sKafORRBB2=";
          openSha256 = "sha256-rQHOOOY4KL92Ww3KDwh+j4eGU7oNAH8LutZC5wmFnPo=";
          settingsSha256 = "sha256-ZEMo8I8Zc2Tq6RVDNYpAH+f094dUaZiBqO+5f6lIjRI=";
          persistencedSha256 = "sha256-ZEMo8I8Zc2Tq6RVDNYpAH+f094dUaZiBqO+5f6lIjRI="; 
      };
    };
  };

  systemd.services.nvidia-target-temperature = {
    enable = false;
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
