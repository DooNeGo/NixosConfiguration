{ pkgs, lib, ... }:

let
  listenAddress = "127.0.0.1";
  listenPort = 2080;
  proxyDomains = [
    "generativelanguage.googleapis.com"
    "aistudio.google.com"
    "openai.com"
    "muse.ai"
    "jetbrains.com"
  ];

  generator = pkgs.writeTextFile {
    name = "sing-box-generate-config.py";
    text = builtins.readFile ./sing-box/generate-config.py;
  };

  fetchSubscription = pkgs.writeShellApplication {
    name = "sing-box-fetch-subscription";
    text = builtins.readFile ./sing-box/fetch-subscription.sh;
    runtimeInputs = with pkgs; [
      curl
      coreutils
      gnused
      gnugrep
    ];
  };
in
{
  services.sing-box.enable = true;

  environment.variables = {
    HTTP_PROXY = "http://${listenAddress}:${toString listenPort}";
    HTTPS_PROXY = "http://${listenAddress}:${toString listenPort}";
    NO_PROXY = "localhost,127.0.0.1,::1,100.64.0.0/10,.ts.net,192.168.0.0/16,10.0.0.0/8";
  };

  systemd = {
    services = {
      sing-box = {
        description = "sing-box VLESS/REALITY proxy (domain-routed)";
        wants = [
          "network-online.target"
          "sing-box-subscription.service"
        ];
        after = [
          "network-online.target"
          "sing-box-subscription.service"
        ];

        environment.SING_BOX_PROXY_DOMAINS = builtins.toJSON proxyDomains;

        serviceConfig = {
          #Type = "simple";
          #RuntimeDirectory = "sing-box";
          #RuntimeDirectoryMode = "0700";
          ExecStartPre = "${pkgs.python3}/bin/python3 ${generator}";
          ExecStart = [
            ""
            "${pkgs.sing-box}/bin/sing-box run -c /run/sing-box/config.json"
          ];
          #Restart = "on-failure";
          #RestartSec = 3;

          LoadCredential = "vless-key:/etc/sing-box/vless-key";
          #NoNewPrivileges = true;
          #ProtectSystem = "strict";
          #ProtectHome = true;
          #PrivateTmp = true;
          #ProtectKernelTunables = true;
          #ProtectControlGroups = true;
          #RestrictAddressFamilies = [
          # "AF_INET"
          # "AF_INET6"
          # "AF_UNIX"
          # "AF_NETLINK"
          #];
        };
      };

      sing-box-subscription = {
        description = "Fetch VLESS subscription into /etc/sing-box/vless-key";
        wantedBy = [ "multi-user.target" ];
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${fetchSubscription}/bin/sing-box-fetch-subscription";
        };
      };
    };

    timers.sing-box-subscription = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "6h";
        Unit = "sing-box-subscription.service";
      };
    };
  };

  age.secrets.vless-subscription-url = {
    enable = true;
    file = ../secrets/vless-subscription-url.age;
    path = "/etc/sing-box/subscription-url";
  };
}
