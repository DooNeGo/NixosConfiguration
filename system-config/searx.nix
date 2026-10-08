{ config, lib, ... }:
let
  # The .age file only exists once the owner has created it (commands below);
  # until then the secret stays disabled so the configuration still evaluates.
  secretKeyPresent = builtins.pathExists ../secrets/searx-secret-key.age;
in
{
  # Owner: from the repo root, create the secret once with
  #   cd /home/shared/NixosConfiguration && agenix -e secrets/searx-secret-key.age
  # (`agenix -e` creates the missing file; recipients come from secrets.nix),
  # then `git add secrets/searx-secret-key.age` (flake eval only sees tracked
  # files). It decrypts at activation to config.age.secrets.searx-secret-key.path
  # (/run/agenix/searx-secret-key), never into the Nix store.
  #
  # Wiring into services.searx is pending an owner decision: the nixpkgs
  # module has no secretKeyFile-style option — secrets are supported only
  # via services.searx.environmentFile ($VAR substitution) or a literal in
  # settings.server.secret_key (would land in the world-readable store).
  age.secrets.searx-secret-key = lib.mkIf secretKeyPresent {
    enable = true;
    mode = "0600";
    owner = "searx";
    group = "searx";
    file = ../secrets/searx-secret-key.age;
  };

  services.searx = {
    enable = true;
    settings = {
      search.formats = [
        "html"
        "json"
      ];
      general.debug = false;

      server = {
        bind_address = "localhost";
        port = 6000;
        #secret_key = cfg.searxngSecretKey;
        image_proxy = true;
      };

      engines = [
        {
          name = "ahmia";
          disabled = true;
        }
        {
          name = "torch";
          disabled = true;
        }
        {
          name = "duckduckgo";
          disabled = true;
        }
        {
          name = "brave";
          disabled = true;
        }
        {
          name = "wikidata";
          disabled = true;
        }
      ];

      search = {
        autocomplete_backend = "none";
      };
    };
  };
}
