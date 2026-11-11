{ pkgs, ... }:
{
  imports = [
    ../shared/zsh.nix
    ../shared/dotnet.nix
    ../shared/git-identity.nix
    ../shared/rider.nix
  ];

  home = {
    username = "DooNeGo";
    homeDirectory = "/Users/DooNeGo";
    stateVersion = "26.05";
    packages = with pkgs; [
      discord
      firefox
      moonlight-qt
      google-chrome
    ];
  };

  programs = {
    home-manager.enable = true;
    fastfetch.enable = true;
    htop.enable = true;
    vscode.enable = true;
  };
}
