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
    # sliding-window counters of the limiter live in a local valkey; the
    # module wires settings.valkey.url to this instance's unix socket
    redisCreateLocally = true;

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
        port = 6080;
        image_proxy = true;
        secret_key = "ggggggggggggggggggggg";
        # bot detection + per-IP rate limiting (docs.searxng.org/admin/searx.limiter.html)
        limiter = true;
        outgoing = {
          proxies."all://" = [ "http://127.0.0.1:2080" ];
        };
      };

      search = {
        autocomplete_backend = "none";
      };
    };

    # rendered to /run/searx/limiter.toml by searx-init; keeping it non-empty
    # also silences the boot warning about the missing limiter.toml. The rate
    # windows themselves (BURST/LONG/API) are hardcoded in searx's
    # botdetection/ip_limit.py and cannot be configured here.
    limiterSettings = {
      botdetection = {
        # upstream default, stated deliberately: link_token would flag the
        # JSON API client (never fetches /client<token>.css) as suspicious and
        # redirect it to / after SUSPICIOUS_IP_MAX requests
        ip_limit.link_token = false;

        # deliberately NOT 127.0.0.0/8: bind_address=localhost routes every
        # client through loopback, a pass entry here would disable the limiter
        # for the whole deployment
        ip_lists.pass_ip = [ ];
      };
    };
  };
}
