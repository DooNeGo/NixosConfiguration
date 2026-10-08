{
  config,
  lib,
  pkgs,
  ...
}:
{
  services.ollama = {
    enable = true;
    acceleration = "cuda";
    host = "127.0.0.1";
    port = 11434;
    environmentVariables = {
      OLLAMA_MODELS = "${config.home.homeDirectory}/.ollama/models";
    };
  };
}
