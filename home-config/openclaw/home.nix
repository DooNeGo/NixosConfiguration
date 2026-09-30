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
    ./sing-box.nix
  ];

  # Local forward proxy for OpenClaw egress (VLESS tunnel, Google-only).
  services.sing-box.enable = true;

  home = {
    inherit username;
    homeDirectory = "/home/${username}";
    stateVersion = "26.05";
    packages = with pkgs; [ ];
  };

  programs.home-manager.enable = true;
}
