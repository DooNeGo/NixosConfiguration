{ pkgs, ... }: {
  programs.tmux = {
    enable = true;
    clock24 = true;
    baseIndex = 1;
    escapeTime = 0;
    plugins = with pkgs.tmuxPlugins; [
      yank
    ];
    extraConfig = ''
      set -g mouse on
    '';
  };
}
