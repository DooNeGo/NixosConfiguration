{
  config,
  pkgs,
  lib,
  ...
}:

let
  mainDomains = [
    "aistudio.google.com"
    "gemini.google.com"
    "googleapis.com"
    "openai.com"
    "chatgpt.com"
    "muse.ai"
    "jetbrains.com"
    "swagger.io"
    "anthropic.com"
    "claude.ai"
    "claude.com"
    "bing.com"
    "microsoft.com"
  ];

  # kind = "vless": credentialFile holds a vless:// link or a subscription URL;
  #                 the -fetch oneshot + timer resolve it into runtimeKey.
  # kind = "awg":   credentialFile holds the server-issued AmneziaWG .conf,
  #                 verbatim. The -awg-prepare oneshot normalises it, wg-quick
  #                 brings up awg.interface with routes in awg.table, and
  #                 sing-box binds its "proxy" outbound to that interface.
  instances = {
    main = {
      kind = "awg";
      listenAddress = "127.0.0.1";
      listenPort = 2080;
      credentialFile = "/etc/sing-box/main-awg.conf";
      proxyDomains = mainDomains;
      routeMatch = "domain_suffix";
      awg = {
        interface = "awg0";
        table = 51820;
      };
    };

    credits-git = {
      kind = "vless";
      listenAddress = "127.0.0.1";
      listenPort = 2081;
      credentialFile = "/etc/sing-box/credits-git-credential";
      runtimeKey = "/etc/sing-box/credits-git-key";
      proxyDomains = [ "gitlab.credits.com" ];
      routeMatch = "domain";
      fetchIntervalSec = 21600;
      onBootSec = "2min";
    };

    credits-stage = {
      kind = "vless";
      listenAddress = "127.0.0.1";
      listenPort = 2082;
      credentialFile = "/etc/sing-box/credits-stage-credential";
      runtimeKey = "/etc/sing-box/credits-stage-key";
      proxyDomains = [
        "mobileapi-stage.credits.com"
        "chats-stage.credits.com"
        "web-wallet-stage.credits.com"
      ];
      routeMatch = "domain";
      fetchIntervalSec = 21600;
      onBootSec = "2min";
    };
  };

  # Instance that HTTP(S)_PROXY points at.
  systemProxy = "main";

  # Must stay below Tailscale's policy rules (5210-5270).
  awgRulePriority = 5000;

  vlessInstances = lib.filterAttrs (_: i: i.kind == "vless") instances;
  awgInstances = lib.filterAttrs (_: i: i.kind == "awg") instances;

  python = "${pkgs.python3}/bin/python3";
  ip = "${pkgs.iproute2}/bin/ip";

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

  prepareAwg = pkgs.writeShellApplication {
    name = "sing-box-prepare-awg";
    text = builtins.readFile ./sing-box/prepare-awg.sh;
    runtimeInputs = with pkgs; [
      coreutils
      gnugrep
      gawk
    ];
  };

  # Runtime files of one AWG interface (written by the -awg-prepare oneshot).
  awgRunDir = inst: "/run/sing-box-awg-${inst.awg.interface}";
  awgConfFile = inst: "${awgRunDir inst}/${inst.awg.interface}.conf"; # 0600 root
  awgAddrFile = inst: "${awgRunDir inst}/address"; # 0644, tunnel IPv4
  awgUnit = inst: "wg-quick-${inst.awg.interface}.service";
  awgSecret = name: config.age.secrets."awg-${name}".file;

  singBoxCmd =
    name:
    "${pkgs.sing-box}/bin/sing-box -D /var/lib/sing-box/${name} -C /etc/sing-box -c /run/sing-box/${name}/config.json";

  proxyInst = instances.${systemProxy};
  proxyUrl = "http://${proxyInst.listenAddress}:${toString proxyInst.listenPort}";
  noProxy = "localhost,127.0.0.1,::1,100.64.0.0/10,.ts.net,192.168.0.0/16,10.0.0.0/8";

  ports = lib.mapAttrsToList (_: i: i.listenPort) instances;
  awgIfaces = lib.mapAttrsToList (_: i: i.awg.interface) awgInstances;
  awgTables = lib.mapAttrsToList (_: i: i.awg.table) awgInstances;
  allUnique = xs: lib.length (lib.unique xs) == lib.length xs;

  mkService =
    name: inst:
    let
      isAwg = inst.kind == "awg";
      deps = [
        "network-online.target"
      ]
      ++ (
        if isAwg then
          [
            "sing-box-${name}-awg-prepare.service"
            (awgUnit inst)
          ]
        else
          [ "sing-box-${name}-fetch.service" ]
      );
    in
    lib.nameValuePair "sing-box-${name}" {
      description = "sing-box instance '${name}' [${inst.kind}] (${toString (builtins.length inst.proxyDomains)} domains -> port ${toString inst.listenPort})";
      # wants, not bindsTo: a tunnel restart must not take the proxy down;
      # sing-box binds every new socket to the interface again.
      wants = deps;
      after = deps;
      wantedBy = [ "multi-user.target" ];
      # the generator bakes the tunnel address into config.json
      restartTriggers = lib.optional isAwg (awgSecret name);
      environment = {
        SING_BOX_KIND = inst.kind;
        SING_BOX_OUT_FILE = "/run/sing-box/${name}/config.json";
        SING_BOX_LISTEN_ADDRESS = inst.listenAddress;
        SING_BOX_LISTEN_PORT = toString inst.listenPort;
        SING_BOX_PROXY_DOMAINS = builtins.toJSON inst.proxyDomains;
        SING_BOX_ROUTE_MATCH = inst.routeMatch;
      }
      // (
        if isAwg then
          {
            SING_BOX_AWG_INTERFACE = inst.awg.interface;
            SING_BOX_AWG_ADDR_FILE = awgAddrFile inst;
          }
        else
          {
            SING_BOX_CREDENTIAL = "${name}-key";
            SING_BOX_TRANSPORT_OVERRIDE = "";
          }
      );
      serviceConfig = {
        Type = "simple";
        User = "sing-box";
        Group = "sing-box";
        RuntimeDirectory = "sing-box/${name}";
        RuntimeDirectoryMode = "0700";
        StateDirectory = "sing-box/${name}";
        StateDirectoryMode = "0700";
        WorkingDirectory = "/var/lib/sing-box/${name}";
        ExecStartPre = [
          "${python} ${generator}"
          "${singBoxCmd name} check"
        ];
        ExecStart = "${singBoxCmd name} run";
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
      }
      // lib.optionalAttrs (!isAwg) {
        LoadCredential = "${name}-key:${inst.runtimeKey}";
      };
    };

  mkFetch =
    name: inst:
    lib.nameValuePair "sing-box-${name}-fetch" {
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
    };

  mkAwgPrepare =
    name: inst:
    lib.nameValuePair "sing-box-${name}-awg-prepare" {
      description = "Normalise the AmneziaWG config of sing-box instance '${name}' for ${inst.awg.interface}";
      requiredBy = [ (awgUnit inst) ];
      before = [ (awgUnit inst) ];
      restartTriggers = [ (awgSecret name) ];
      environment = {
        AWG_SOURCE_FILE = inst.credentialFile;
        AWG_OUT_FILE = awgConfFile inst;
        AWG_ADDR_FILE = awgAddrFile inst;
        AWG_TABLE = toString inst.awg.table;
      };
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = "yes";
        RuntimeDirectory = "sing-box-awg-${inst.awg.interface}";
        RuntimeDirectoryMode = "0755";
        RuntimeDirectoryPreserve = "yes";
        ExecStart = "${prepareAwg}/bin/sing-box-prepare-awg";
      };
    };

  # Extends the unit generated by networking.wg-quick: ordering plus the
  # policy rule that sends packets sourced from the tunnel address to awg.table.
  mkAwgIface =
    name: inst:
    let
      prepare = "sing-box-${name}-awg-prepare.service";
      table = toString inst.awg.table;
      prio = toString awgRulePriority;
      addrFile = awgAddrFile inst;
    in
    lib.nameValuePair "wg-quick-${inst.awg.interface}" {
      requires = [ prepare ];
      after = [ prepare ];
      restartTriggers = [ (awgSecret name) ];
      postStart = ''
        addr=$(cat ${addrFile})
        ${ip} -4 rule del from "$addr" lookup ${table} priority ${prio} 2>/dev/null || true
        ${ip} -4 rule add from "$addr" lookup ${table} priority ${prio}
      '';
      postStop = ''
        if [ -r ${addrFile} ]; then
          ${ip} -4 rule del from "$(cat ${addrFile})" lookup ${table} priority ${prio} 2>/dev/null || true
        fi
      '';
    };
in
assert allUnique ports;
assert lib.all (i: i.proxyDomains != [ ]) (lib.attrValues instances);
assert lib.all (n: (builtins.match "[a-z][a-z0-9_-]*" n) != null) (lib.attrNames instances);
assert lib.all (
  i:
  builtins.elem i.routeMatch [
    "domain"
    "domain_suffix"
  ]
) (lib.attrValues instances);
assert lib.all (
  i:
  builtins.elem i.kind [
    "vless"
    "awg"
  ]
) (lib.attrValues instances);
assert lib.all (i: lib.hasPrefix "/etc/" i.credentialFile) (lib.attrValues instances);
assert lib.all (i: lib.hasPrefix "/etc/" i.runtimeKey) (lib.attrValues vlessInstances);
assert builtins.hasAttr systemProxy instances;
# kernel limit: interface names are at most 15 characters
assert lib.all (n: (builtins.match "[a-z][a-z0-9]{0,14}" n) != null) awgIfaces;
assert allUnique awgIfaces;
# 0 and 253-255 are reserved, 52 is Tailscale's table
assert lib.all (t: builtins.isInt t && t > 255) awgTables;
assert allUnique awgTables;
{
  environment.systemPackages = [ pkgs.sing-box ];

  users.users."sing-box" = {
    isSystemUser = true;
    group = "sing-box";
    home = "/var/lib/sing-box";
  };
  users.groups."sing-box" = { };

  environment.variables = {
    HTTP_PROXY = proxyUrl;
    HTTPS_PROXY = proxyUrl;
    NO_PROXY = noProxy;
    http_proxy = proxyUrl;
    https_proxy = proxyUrl;
    no_proxy = noProxy;
  };

  # type = "amneziawg" pulls in the kernel module and amneziawg-tools.
  networking.wg-quick.interfaces = lib.mapAttrs' (
    _: inst:
    lib.nameValuePair inst.awg.interface {
      type = "amneziawg";
      configFile = awgConfFile inst;
    }
  ) awgInstances;

  systemd.services = lib.listToAttrs (
    lib.mapAttrsToList mkService instances
    ++ lib.mapAttrsToList mkFetch vlessInstances
    ++ lib.mapAttrsToList mkAwgPrepare awgInstances
    ++ lib.mapAttrsToList mkAwgIface awgInstances
  );

  systemd.timers = lib.mapAttrs' (
    name: inst:
    lib.nameValuePair "sing-box-${name}-fetch" {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = inst.onBootSec;
        OnUnitActiveSec = toString inst.fetchIntervalSec;
        Unit = "sing-box-${name}-fetch.service";
      };
    }
  ) vlessInstances;

  # vless-<name>.age: link or subscription URL; awg-<name>.age: AmneziaWG .conf
  age.secrets = lib.mapAttrs' (
    name: inst:
    lib.nameValuePair "${inst.kind}-${name}" {
      enable = true;
      mode = "0600";
      file = ../../secrets/${inst.kind}-${name}.age;
      path = inst.credentialFile;
    }
  ) instances;
}
