{ lib, pkgs, ... }:
let
  settings = foreground: background: {
    add_newline = false;
    format = "[](fg:${background})$username$hostname$directory$git_branch$git_status$nix_shell$cmd_duration[ ](bg:${background})[](fg:${background}) $character";

    username = {
      show_always = true;
      format = "[ $user](fg:${foreground} bg:${background})";
    };
    # Only in an ssh session: on the machine itself the host name is known.
    hostname = {
      ssh_only = true;
      format = "[  $hostname](fg:${foreground} bg:${background})";
    };
    directory = {
      truncation_length = 3;
      format = "[  $path](fg:${foreground} bg:${background})";
    };
    git_branch = {
      symbol = " ";
      format = "[  $symbol$branch](fg:${foreground} bg:${background})";
    };
    git_status.format = "([  $all_status$ahead_behind](fg:${foreground} bg:${background}))";
    nix_shell = {
      symbol = " ";
      format = "[  $symbol$state](fg:${foreground} bg:${background})";
    };
    cmd_duration = {
      min_time = 2000;
      format = "[   $duration](fg:${foreground} bg:${background})";
    };
    character = {
      success_symbol = "[❯](bold blue)";
      error_symbol = "[❯](bold red)";
    };
  };
  kittyConfig = (pkgs.formats.toml { }).generate "starship-kitty.toml" (settings "16" "17");
in
{
  programs = {
    zsh = {
      syntaxHighlighting.enable = true;
      autosuggestion.highlight = "fg=8";
      initContent = lib.mkBefore ''
        if [[ ''${MATHEW_KITTY_PALETTE:-} == 1 && -z ''${SSH_CONNECTION:-} && -z ''${STARSHIP_CONFIG:-} ]]; then
          export STARSHIP_CONFIG=${kittyConfig}
        fi
      '';
    };
    starship = {
      enable = true;
      enableZshIntegration = true;
      settings = settings "black" "blue";
    };
  };
}
