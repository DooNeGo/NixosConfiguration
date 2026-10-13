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
    packages = with pkgs.unstable; [
      ungoogled-chromium
      # только chattr/lsattr: полный e2fsprogs конфликтует с androidsdk (mke2fs)
      (pkgs.runCommand "e2fsprogs-attr" { } ''
        mkdir -p $out/bin
        ln -s ${e2fsprogs}/bin/chattr ${e2fsprogs}/bin/lsattr $out/bin/
      '')
    ];
  };

  programs = {
    home-manager.enable = true;
    antigravity-cli.enable = true;
    claude-code = {
      enable = true;
      package = pkgs.unstable.claude-code;
    };
  };
}
