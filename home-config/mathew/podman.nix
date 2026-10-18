{ pkgs, ... }:
{
  services.podman = {
    enable = true;
    settings.storage = {
      driver = "btrfs";
    };
  };

  home.packages = [
    pkgs.podman-compose
  ];
}
