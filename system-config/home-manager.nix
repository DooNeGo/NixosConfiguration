{ config, pkgs, lib, ... }:

let
  home-manager = builtins.fetchTarball https://github.com/nix-community/home-manager/archive/release-25.05.tar.gz;
in
{
  imports = [ (import "${home-manager}/nixos") ];

  home-manager.users.mathew = { pkgs, ... }: {
    home.stateVersion = "25.05";
    programs.home-manager.enable = true;
  };
}
