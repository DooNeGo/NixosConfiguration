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
    ../shared/ssh.nix
  ];

  home = {
    inherit username;
    homeDirectory = "/home/${username}";
    stateVersion = "26.05";
    packages = with pkgs; [
      ungoogled-chromium
    ];
  };

  programs = {
    home-manager.enable = true;
    antigravity-cli.enable = true;
    claude-code.enable = true;
  };
}
