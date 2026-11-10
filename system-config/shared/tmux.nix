# Written through extraConfig only: NixOS and nix-darwin share no other programs.tmux options.
{ pkgs, ... }:
{
  programs.tmux = {
    enable = true;
    extraConfig = ''
      set -g base-index 1
      setw -g pane-base-index 1
      setw -g clock-mode-style 24
      set -s escape-time 0
      set -g mouse on
      set -g renumber-windows on
      set -g focus-events on
      run-shell ${pkgs.tmuxPlugins.yank}/share/tmux-plugins/yank/yank.tmux
    '';
  };
}
