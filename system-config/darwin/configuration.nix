{
  pkgs,
  inputs,
  user,
  ...
}:
{
  imports = [
    ../shared/nix-settings.nix
    ../shared/nh.nix
    ../shared/tmux.nix
    ../shared/vim.nix
  ];

  system = {
    primaryUser = user;
    stateVersion = 6;
    configurationRevision = inputs.self.rev or inputs.self.dirtyRev or null;

    defaults.dock = {
      tilesize = 55;
      largesize = 75;
      autohide = false;
      mineffect = "genie";
    };
  };

  networking.hostName = "macbook-air-m1";

  services.tailscale.enable = true;

  environment.systemPackages = with pkgs; [
    home-manager
    watch
    tailscale-gui
  ];

  launchd.user.agents.autoraise = {
    command = "${pkgs.autoraise}/bin/autoraise -delay 2 -pollMillis 50";
    serviceConfig = {
      KeepAlive = true;
      RunAtLoad = true;
    };
  };

  nix.settings.auto-optimise-store = true;

  nixpkgs.hostPlatform = "aarch64-darwin";
  security.pam.services.sudo_local.touchIdAuth = true;
}
