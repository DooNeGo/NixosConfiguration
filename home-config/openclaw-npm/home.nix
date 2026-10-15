{ pkgs, ... }:
{
  imports = [
    ../shared/zsh.nix
    ../shared/git.nix
  ];

  home = {
    username = "openclaw-npm";
    homeDirectory = "/home/openclaw-npm";
    stateVersion = "26.05";

    packages = with pkgs; [
      #git
      jq
      curl
      ungoogled-chromium
      e2fsprogs
      psmisc
      pkgs.unstable.yt-dlp
      #(pkgs.runCommand "e2fsprogs-attr" { } ''
        #mkdir -p $out/bin
        #ln -s ${e2fsprogs}/bin/chattr ${e2fsprogs}/bin/lsattr $out/bin/
      #'')
    ];

    sessionVariables = {
      "OPENCLAW_GATEWAY_PORT" = "19001";
      #NPM_CONFIG_PREFIX = "$HOME/.npm-global";
    };

    sessionPath = [
      "$HOME/.npm/bin"
      "$HOME/.local/share/pnpm"
    ];
  };

  programs = {
    home-manager.enable = true;
    npm = {
      enable = true;
      package = pkgs.unstable.nodejs_latest;
    };
    pnpm.enable = true;
    claude-code = {
      enable = true;
      package = pkgs.unstable.claude-code;
    };
  };
}
