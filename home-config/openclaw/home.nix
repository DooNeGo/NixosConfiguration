{
  pkgs,
  config,
  inputs,
  username,
  ...
}:
{
  imports = [
    ./openclaw.nix
    ./ollama.nix
    ./speech.nix
    ../shared/zsh.nix
    ../shared/maui-dev.nix
  ];

  home = {
    inherit username;
    homeDirectory = "/home/${username}";
    stateVersion = "26.05";
    packages = with pkgs; [
      ungoogled-chromium
    ];
  };

  programs.home-manager.enable = true;
}
