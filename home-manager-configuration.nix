{ config, pkgs, lib, ... }:

let
  home-manager = builtins.fetchTarball https://github.com/nix-community/home-manager/archive/release-25.05.tar.gz;
in
{
  imports = [ (import "${home-manager}/nixos") ];

  home-manager.users.game = { pkgs, ... }: {
    home.packages = with pkgs; [ mangohud proton-ge-bin ];

    programs = {
      bash.enable = true;

      steam = {
        enable = true;
        gamescopeSession.enable = true;
      };

      gamescope = {
        enable = true;
        capSysNice = true;
      };
    };

    home.stateVersion = "25.05";
  };

  home-manager.users.work = { pkgs, ... }: {
  };
}
