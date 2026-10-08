{
  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    initContent = ''
      # OpenClaw CLI completions (zsh)
      if (( $+commands[openclaw] )); then
        source <(openclaw completion -s zsh 2>/dev/null)
      fi
    '';
  };
}
