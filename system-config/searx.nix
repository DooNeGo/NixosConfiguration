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
    #redisCreateLocally = true;

    settings = {
      search.formats = [
        "html"
        "json"
      ];
      general.debug = false;

      outgoing = {
        request_timeout = 6.0;
      };

      server = {
        bind_address = "localhost";
        port = 6081;
        image_proxy = true;
        secret_key = "ggggggggggggggggggggg";
        limiter = false;
        outgoing = {
          proxies."all://" = [ "http://127.0.0.1:2080" ];
        };
      };

      search = {
        autocomplete_backend = "none";
      };

      engines = [
        {
          name = "brave";
          disabled = true;
        }
        {
          name = "duckduckgo";
          disabled = true;
        }
      ];
    };

    limiterSettings = {
      botdetection = {
        ip_limit.link_token = false;
        ip_lists.pass_ip = [
          "127.0.0.0/8"
          "::1/128"
        ];
      };
    };
  };

  services.nginx = {
    enable = true;

    commonHttpConfig = ''
      limit_req_zone $binary_remote_addr zone=searx_spacing:1m rate=1r/s;
    '';

    virtualHosts."localhost" = {
      listen = [
        {
          addr = "127.0.0.1";
          port = 6080;
        }
      ];
      locations."/" = {
        proxyPass = "http://127.0.0.1:6081";
        extraConfig = ''
          limit_req zone=searx_spacing burst=20;
          limit_req_status 503;
          proxy_connect_timeout 10s;
          proxy_read_timeout 60s;
          proxy_send_timeout 60s;
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        '';
      };
    };
  };
}
