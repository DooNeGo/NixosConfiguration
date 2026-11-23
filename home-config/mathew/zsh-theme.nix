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

        # One pill: the fill is ANSI blue (the wallpaper's primary colour), the text is colour 16, which the kitty palette
        # sets to the text colour of an accent fill (dark on the light accent of the dark mode, white on the dark accent
        # of the light mode; a terminal without that palette shows its black there) and the modules are split by a thin
        # Powerline arrow. The caps are half-circle glyphs in
        # the fill colour, so the fill stays opaque. The command is typed on the same line.
        username = {
          show_always = true;
          format = "[ $user](fg:16 bg:blue)";
        };
        # Only in an ssh session: on the machine itself the host name is known.
        hostname = {
          ssh_only = true;
          format = "[  $hostname](fg:16 bg:blue)";
        };
        directory = {
          truncation_length = 3;
          format = "[  $path](fg:16 bg:blue)";
        };
        git_branch = {
          symbol = " ";
          format = "[  $symbol$branch](fg:16 bg:blue)";
        };
        git_status.format = "([  $all_status$ahead_behind](fg:16 bg:blue))";
        nix_shell = {
          symbol = " ";
          format = "[  $symbol$state](fg:16 bg:blue)";
        };
        cmd_duration = {
          min_time = 2000;
          format = "[   $duration](fg:16 bg:blue)";
        };
        character = {
          success_symbol = "[❯](bold blue)";
          error_symbol = "[❯](bold red)";
        };
      };
    };
  };
}
