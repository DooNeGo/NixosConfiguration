{ config, lib, ... }:
{
  options.generationsKeep = lib.mkOption {
    type = lib.types.ints.positive;
    default = 20;
    description = ''
      How many system generations to keep: nh clean never removes that many newest ones, and on NixOS the boot menu
      lists as many entries, so no entry points at a collected generation.
    '';
  };

  config.programs.nh = {
    enable = true;
    clean = {
      enable = true;
      extraArgs = "--keep-since 14d --keep ${toString config.generationsKeep}";
    };
  };
}
