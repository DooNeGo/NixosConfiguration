{
  pkgs,
  inputs,
  user,
  ...
}:
{
  imports = [
    ../shared/nix-settings.nix
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

  # The user's Home Manager configuration is a separate flake (home-config/DooNeGo), applied with this CLI.
  environment.systemPackages = [
    pkgs.home-manager
    pkgs.watch
  ];

  nix.settings.auto-optimise-store = true;

  nixpkgs.hostPlatform = "aarch64-darwin";
  security.pam.services.sudo_local.touchIdAuth = true;
}
