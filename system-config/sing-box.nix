{ pkgs, lib, ... }:

let
  instances = {
    main = {
      listenAddress = "127.0.0.1";
      listenPort = 2080;
      credentialFile = "/etc/sing-box/main-credential";
      runtimeKey = "/etc/sing-box/main-key";
      proxyDomains = [
        "aistudio.google.com"
        "gemini.google.com"
        "openai.com"
        "muse.ai"
        "jetbrains.com"
        "mobileapi-stage.credits.com"
        "swagger.io"
        "github.com"
        "googleapis.com"
        "anthropic.com"
      ];
      routeMatch = "domain_suffix";
      fetchIntervalSec = 21600;
      onBootSec = "2min";
    };

    credits-git = {
      listenAddress = "127.0.0.1";
      listenPort = 2081;
      credentialFile = "/etc/sing-box/credits-git-credential";
      runtimeKey = "/etc/sing-box/credits-git-key";
      proxyDomains = [ "gitlab.credits.com" ];
      routeMatch = "domain";
      fetchIntervalSec = 21600;
      onBootSec = "2min";
    };
  };

  python = "${pkgs.python3}/bin/python3";

  generator = pkgs.writeTextFile {
    name = "sing-box-generate-config.py";
    text = builtins.readFile ./sing-box/generate-config.py;
  };

  resolveCredential = pkgs.writeShellApplication {
    name = "sing-box-resolve-credential";
    text = builtins.readFile ./sing-box/resolve-credential.sh;
    runtimeInputs = with pkgs; [
      curl
      coreutils
      gnused
      gnugrep
    ];
  };

  main = instances.main;

  ports = lib.attrValues (lib.mapAttrs (_: i: i.listenPort) instances);
  proxyPort = toString main.listenPort;
in
assert lib.length (lib.unique ports) == lib.length ports;
assert lib.all (i: i.proxyDomains != [ ]) (lib.attrValues instances);
assert lib.all (n: (builtins.match "[a-z][a-z0-9_-]*" n) != null) (lib.attrNames instances);
assert lib.all (
  i:
  builtins.elem i.routeMatch [
    "domain"
    "domain_suffix"
  ]
) (lib.attrValues instances);
assert lib.all (i: lib.hasPrefix "/etc/" i.credentialFile) (lib.attrValues instances);
assert lib.all (i: lib.hasPrefix "/etc/" i.runtimeKey) (lib.attrValues instances);
{
  environment.systemPackages = [ pkgs.sing-box ];

  users.users."sing-box" = {
    isSystemUser = true;
    group = "sing-box";
    home = "/var/lib/sing-box";
  };
  users.groups."sing-box" = { };

  environment.variables = {
    HTTP_PROXY = "http://${main.listenAddress}:${proxyPort}";
    HTTPS_PROXY = "http://${main.listenAddress}:${proxyPort}";
    NO_PROXY = "localhost,127.0.0.1,::1,100.64.0.0/10,.ts.net,192.168.0.0/16,10.0.0.0/8";
  };

  systemd.services = lib.listToAttrs (
    lib.flatten (
      lib.mapAttrsToList (name: inst: [
        (lib.nameValuePair "sing-box-${name}" {
          description = "sing-box instance '${name}' (${toString (builtins.length inst.proxyDomains)} domains -> port ${toString inst.listenPort})";
          wants = [
            "network-online.target"
            "sing-box-${name}-fetch.service"
          ];
          after = [
            "network-online.target"
            "sing-box-${name}-fetch.service"
          ];
          wantedBy = [ "multi-user.target" ];
          environment = {
            SING_BOX_CREDENTIAL = "${name}-key";
            SING_BOX_OUT_FILE = "/run/sing-box/${name}/config.json";
            SING_BOX_LISTEN_ADDRESS = inst.listenAddress;
            SING_BOX_LISTEN_PORT = toString inst.listenPort;
            SING_BOX_PROXY_DOMAINS = builtins.toJSON inst.proxyDomains;
            SING_BOX_ROUTE_MATCH = inst.routeMatch;
            SING_BOX_TRANSPORT_OVERRIDE = "";
          };
          serviceConfig = {
            Type = "simple";
            User = "sing-box";
            Group = "sing-box";
            RuntimeDirectory = "sing-box/${name}";
            RuntimeDirectoryMode = "0700";
            StateDirectory = "sing-box/${name}";
            StateDirectoryMode = "0700";
            WorkingDirectory = "/var/lib/sing-box/${name}";
            ExecStartPre = "${python} ${generator}";
            LoadCredential = "${name}-key:${inst.runtimeKey}";
            ExecStart = "${pkgs.sing-box}/bin/sing-box -D /var/lib/sing-box/${name} -C /etc/sing-box -c /run/sing-box/${name}/config.json run";
            Restart = "on-failure";
            RestartSec = 3;
            LimitNOFILE = "infinity";
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
        })
        (lib.nameValuePair "sing-box-${name}-fetch" {
          description = "Resolve sing-box credential for instance '${name}' into the runtime key";
          wantedBy = [ "multi-user.target" ];
          wants = [ "network-online.target" ];
          after = [ "network-online.target" ];
          environment = {
            SING_BOX_CREDENTIAL_FILE = inst.credentialFile;
            SING_BOX_KEY_FILE = inst.runtimeKey;
          };
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = "yes";
            ExecStart = "${resolveCredential}/bin/sing-box-resolve-credential";
          };
        })
      ]) instances
    )
  );

  systemd.timers = lib.listToAttrs (
    lib.mapAttrsToList (
      name: inst:
      lib.nameValuePair "sing-box-${name}-fetch" {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = inst.onBootSec;
          OnUnitActiveSec = toString inst.fetchIntervalSec;
          Unit = "sing-box-${name}-fetch.service";
        };
      }
    ) instances
  );

  age.secrets = lib.mapAttrs' (
    name: inst:
    lib.nameValuePair "vless-${name}" {
      enable = true;
      mode = "0600";
      file = ../secrets/vless-${name}.age;
      path = inst.credentialFile;
    }
  ) instances;
}
