{ pkgs, ... }: {
  virtualisation = {
    containers.enable = true;

    podman = {
      enable = true;
      dockerCompat = true;
      autoPrune.enable = true;
      defaultNetwork.settings.dns_enabled = true;
    };

    containers.storage.settings = {
      storage = {
        driver = "btrfs";
      };
    };
  };

  environment.systemPackages = [ pkgs.podman-compose ];
  users.users.mathew.extraGroups = [ "podman" ];
}
