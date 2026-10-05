{
  config,
  lib,
  pkgs,
  ...
}:
{
  # Local LLM/embeddings server (home level, user service).
  # Module: nix-community/home-manager modules/services/ollama.nix
  services.ollama = {
    enable = true;
    acceleration = false; # CPU only
    host = "127.0.0.1";
    port = 11434;
    environmentVariables = {
      # Keep model cache inside the user dir (survives rebuilds)
      OLLAMA_MODELS = "${config.home.homeDirectory}/.ollama/models";
    };
  };

  # Client CLI (ollama run / pull) — the module already adds the server
  # package to home.packages, so no separate entry needed.
}
