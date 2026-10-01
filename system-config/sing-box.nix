# sing-box: system-level VLESS/REALITY proxy with domain-based routing.
#
# The VLESS credential never enters the Nix store. The service loads it as a
# systemd credential from /etc/sing-box/vless-key (root-owned, 0600, created
# manually once outside Nix): at service start it is bind-mounted read-only to
# /run/credentials/sing-box/vless-key, and a PreStart script
# (./sing-box/generate-config.py) reads it from there and writes
# /run/sing-box/config.json (mode 0600). Only the mixed inbound + routing live
# here.
{ pkgs, lib, ... }:

let
  listenAddress = "127.0.0.1";
  listenPort = 2080;

  # Everything below is proxied; everything else goes direct.
  # Extend this list to route more domains through the proxy.
  proxyDomains = [
    # Google API / Gemini
    "generativelanguage.googleapis.com"
    "aistudio.google.com"
    # OpenAI (covers api. / cdn. etc.)
    "openai.com"
    # Muse (covers api.muse.ai)
    "muse.ai"
    # JetBrains (download / data.services / plugins / account ...)
    "jetbrains.com"
  ];

  generator = pkgs.writeTextFile {
    name = "sing-box-generate-config.py";
    text = builtins.readFile ./sing-box/generate-config.py;
  };
in
{
  # System-wide proxy env (-> /etc/environment). Inherited by login sessions,
  # the systemd user manager (and thus user services such as openclaw-gateway),
  # GUI apps (Rider/Toolbox) and anything else that honours these variables.
  environment.variables = {
    HTTP_PROXY = "http://${listenAddress}:${toString listenPort}";
    HTTPS_PROXY = "http://${listenAddress}:${toString listenPort}";
    NO_PROXY = "localhost,127.0.0.1,::1,100.64.0.0/10,.ts.net,192.168.0.0/16,10.0.0.0/8";
  };

  systemd.services.sing-box = {
    description = "sing-box VLESS/REALITY proxy (domain-routed)";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];

    environment.SING_BOX_PROXY_DOMAINS = builtins.toJSON proxyDomains;

    serviceConfig = {
      Type = "simple";
      RuntimeDirectory = "sing-box";
      RuntimeDirectoryMode = "0700";
      ExecStartPre = "${pkgs.python3}/bin/python3 ${generator}";
      ExecStart = "${pkgs.sing-box}/bin/sing-box run -c /run/sing-box/config.json";
      Restart = "on-failure";
      RestartSec = 3;

      # Hardening (the service only needs the credential + serve loopback).
      LoadCredential = "vless-key:/etc/sing-box/vless-key";
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      ProtectKernelTunables = true;
      ProtectControlGroups = true;
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_UNIX"
        "AF_NETLINK"
      ];
    };
  };
}
