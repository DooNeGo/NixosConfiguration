{
  config,
  pkgs,
  lib,
  ...
}:
{
  imports = [
    ../shared/zsh.nix
    ../shared/git.nix
    ../shared/ssh.nix
    ../shared/maui-dev.nix
  ];

  home = {
    username = "openclaw-npm";
    homeDirectory = "/home/openclaw-npm";
    stateVersion = "26.05";

    packages = with pkgs; [
      jq
      curl
      ungoogled-chromium
      (lib.hiPrio e2fsprogs)
      psmisc
      yt-dlp
      python3
    ];

    sessionVariables = {
      "WHISPER_CPP_MODEL" = "/var/lib/whisper-cpp/ggml-small.bin";
      "QT_QPA_PLATFORM" = "offscreen";
    };

    sessionPath = [
      "$HOME/.npm/bin"
      "$HOME/.local/bin"
      "${config.programs.claude-code.package}/bin"
      "${config.programs.codex.package}/bin"
    ];
  };

  programs = {
    home-manager.enable = true;
    codex.enable = true;

    npm = {
      enable = true;
      package = pkgs.nodejs_latest;
    };

    claude-code = {
      enable = true;
      package = pkgs.claude-code;
    };

    zsh.initContent = ''
      # OpenClaw Completion
      [ -f '/home/openclaw-npm/.openclaw/completions/openclaw.zsh' ] && source '/home/openclaw-npm/.openclaw/completions/openclaw.zsh'
    '';
  };
}
