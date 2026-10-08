{ config, lib, ... }:
{
  age.secrets.searx-secret-key = {
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

      outgoing = {
        proxies."all://" = [ "http://127.0.0.1:2080" ];
        request_timeout = 6.0;
      };

      server = {
        bind_address = "localhost";
        port = 6080;
        image_proxy = true;
        secret_key = "ggggggggggggggggggggg";
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
