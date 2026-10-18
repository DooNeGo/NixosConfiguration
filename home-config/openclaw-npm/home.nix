{ pkgs, lib, ... }:
{
  imports = [
    ../shared/zsh.nix
    ../shared/git.nix
    ../shared/maui-dev.nix
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
      (lib.hiPrio e2fsprogs)
      psmisc
      yt-dlp
      python3
      #(pkgs.runCommand "e2fsprogs-attr" { } ''
      #mkdir -p $out/bin
      #ln -s ${e2fsprogs}/bin/chattr ${e2fsprogs}/bin/lsattr $out/bin/
      #'')
    ];

    sessionVariables = {
      "WHISPER_CPP_MODEL" = "/var/lib/whisper-cpp/ggml-small.bin";
      #NPM_CONFIG_PREFIX = "$HOME/.npm-global";
    };

    sessionPath = [
      "$HOME/.npm/bin"
    ];
  };

  programs = {
    home-manager.enable = true;
    codex.enable = true;

    npm = {
      enable = true;
      package = pkgs.unstable.nodejs_latest;
    };

    claude-code = {
      enable = true;
      package = pkgs.unstable.claude-code;
    };

    zsh.initContent = ''
      # OpenClaw Completion
      [ -f '/home/openclaw-npm/.openclaw/completions/openclaw.zsh' ] && source '/home/openclaw-npm/.openclaw/completions/openclaw.zsh'
    '';
  };
}
