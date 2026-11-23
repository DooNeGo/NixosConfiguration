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
        format = "[](fg:17)$username$hostname$directory$git_branch$git_status$nix_shell$cmd_duration[ ](bg:17)[](fg:17) $character";

        # One pill: the fill is colour 17 and the text colour 16, which the kitty palette sets to the container of the
        # accent (a dark fill with light text in the dark mode, a light fill with dark text in the light mode; a terminal
        # without that palette shows colours of the 256-colour cube) and the modules are split by a thin Powerline arrow.
        # The caps are half-circle Powerline glyphs in the fill colour, so the fill stays opaque. The command is typed on
        # the same line.
        username = {
          show_always = true;
          format = "[ $user](fg:16 bg:17)";
        };
        # Only in an ssh session: on the machine itself the host name is known.
        hostname = {
          ssh_only = true;
          format = "[  $hostname](fg:16 bg:17)";
        };
        directory = {
          truncation_length = 3;
          format = "[  $path](fg:16 bg:17)";
        };
        git_branch = {
          symbol = " ";
          format = "[  $symbol$branch](fg:16 bg:17)";
        };
        git_status.format = "([  $all_status$ahead_behind](fg:16 bg:17))";
        nix_shell = {
          symbol = " ";
          format = "[  $symbol$state](fg:16 bg:17)";
        };
        cmd_duration = {
          min_time = 2000;
          format = "[   $duration](fg:16 bg:17)";
        };
        character = {
          success_symbol = "[❯](bold blue)";
          error_symbol = "[❯](bold red)";
        };
      };
    };
  };
}
