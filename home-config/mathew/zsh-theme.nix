{
  # Colours come from the ANSI palette that kitty takes from the wallpaper (palette/kitty.conf), so the highlighter,
  # the suggestions and the prompt change with the wallpaper without a palette of their own.
  programs = {
    zsh = {
      syntaxHighlighting.enable = true;
      autosuggestion.highlight = "fg=8";
    };

    starship = {
      enable = true;
      enableZshIntegration = true;
      settings = {
        add_newline = false;
        format = "[](fg:blue)$username$hostname$directory$git_branch$git_status$nix_shell$cmd_duration[ ](bg:blue)[](fg:blue) $character";

        # One pill: the fill is ANSI blue (the wallpaper's primary colour), the text is ANSI black (dark, so it contrasts
        # with the light primary) and the modules are split by a thin Powerline arrow. The caps are half-circle glyphs in
        # the fill colour, so the fill stays opaque. The command is typed on the same line.
        username = {
          show_always = true;
          format = "[ $user](fg:black bg:blue)";
        };
        # Only in an ssh session: on the machine itself the host name is known.
        hostname = {
          ssh_only = true;
          format = "[  $hostname](fg:black bg:blue)";
        };
        directory = {
          truncation_length = 3;
          format = "[  $path](fg:black bg:blue)";
        };
        git_branch = {
          symbol = " ";
          format = "[  $symbol$branch](fg:black bg:blue)";
        };
        git_status.format = "([  $all_status$ahead_behind](fg:black bg:blue))";
        nix_shell = {
          symbol = " ";
          format = "[  $symbol$state](fg:black bg:blue)";
        };
        cmd_duration = {
          min_time = 2000;
          format = "[   $duration](fg:black bg:blue)";
        };
        character = {
          success_symbol = "[❯](bold blue)";
          error_symbol = "[❯](bold red)";
        };
      };
    };
  };
}
