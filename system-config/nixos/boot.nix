{ config, pkgs, ... }:
{
  boot = {
    loader.systemd-boot = {
      enable = true;
      configurationLimit = config.generationsKeep;
    };

    loader.efi.canTouchEfiVariables = true;

    supportedFilesystems = [ "btrfs" ];

    kernelModules = [ "ntsync" ];

    kernelPackages = pkgs.linuxPackages_latest;

    tmp = {
      useTmpfs = true;
      tmpfsSize = "50%";
      tmpfsHugeMemoryPages = "within_size";
    };

    kernel.sysctl."vm.admin_reserve_kbytes" = 131072;
  };

  powerManagement.cpuFreqGovernor = "performance";
}
