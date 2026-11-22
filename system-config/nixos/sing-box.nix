{
  config,
  pkgs,
  lib,
  ...
}:

let
  # exitNode = true (kind "awg" only, at most one instance): the Tailscale exit
  #                 node forwards into this instance's tunnel (awg-exit-node.nix).
  # kind = "vless": credentialFile holds a vless:// link, a subscription URL or an
  #                 Amnezia vpn:// string with an xray container;
  #                 the -fetch oneshot + timer resolve it into runtimeKey.
  # kind = "awg":   credentialFile holds the server-issued AmneziaWG .conf or an
  #                 Amnezia vpn:// string, verbatim. The -awg-prepare oneshot
  #                 normalises it, wg-quick brings up awg.interface with routes
  #                 in awg.table, and sing-box binds its "proxy" outbound to
  #                 that interface.
  instances = {
    main = {
      kind = "awg";
      exitNode = true;
      listenAddress = "127.0.0.1";
      listenPort = 2080;
      credentialFile = "/etc/sing-box/main-awg.conf";
      proxyDomains = [
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
      routeMatch = "domain_suffix";
      awg = {
        interface = "awg0";
        table = 51820;
      };
    };

    credits = {
      kind = "vless";
      listenAddress = "127.0.0.1";
      listenPort = 2081;
      credentialFile = "/etc/sing-box/credits-credential";
      runtimeKey = "/etc/sing-box/credits-key";
      proxyDomains = [
        "gitlab.credits.com"
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

  python = "${pkgs.python3}/bin/python3";

  decodeVpn = pkgs.writeTextFile {
    name = "sing-box-decode-vpn.py";
    text = builtins.readFile ./sing-box/decode-vpn.py;
  };

  singBoxCmd =
    name:
    "${pkgs.sing-box}/bin/sing-box -D /var/lib/sing-box/${name} -C /etc/sing-box -c /run/sing-box/${name}/config.json";

  proxyInst =
    instances.${systemProxy} or (throw "sing-box.nix: systemProxy '${systemProxy}' is not an instance");
  proxyUrl = "http://${proxyInst.listenAddress}:${toString proxyInst.listenPort}";
  noProxy = "localhost,127.0.0.1,::1,100.64.0.0/10,.ts.net,192.168.0.0/16,10.0.0.0/8";

  ports = lib.mapAttrsToList (_: i: i.listenPort) instances;
  allUnique = xs: lib.length (lib.unique xs) == lib.length xs;

  shared = { inherit decodeVpn; };

  kindFiles = {
    awg = ./sing-box/kinds/awg.nix;
    vless = ./sing-box/kinds/vless.nix;
  };

  # Python imports `kinds` from the real directory of the script, so the files are copied, not linked.
  generator = pkgs.runCommand "sing-box-generator" { } ''
    install -D ${./sing-box/generate-config.py} $out/generate-config.py
    ${lib.concatMapStrings (k: "install -D ${./sing-box/kinds + "/${k}.py"} $out/kinds/${k}.py\n") (
      lib.attrNames kindFiles
    )}
    touch $out/kinds/__init__.py
  '';

  kindDefaults = {
    services = { };
    timers = { };
    extraConfig = { };
    deps = [ ];
    restartTriggers = [ ];
    environment = { };
    serviceConfig = { };
    failureUnits = [ ];
    exitTunnel = null;
    claims = { };
    assertions = [ ];
  };

  kindResult =
    name: inst:
    let
      result =
        import
          (kindFiles.${inst.kind}
            or (throw "sing-box instance '${name}': unknown kind '${inst.kind}', expected one of ${toString (lib.attrNames kindFiles)}")
          )
          {
            inherit
              pkgs
              lib
              name
              inst
              shared
              ;
            secretFile = config.age.secrets."${inst.kind}-${name}".file;
          };
      unknown = lib.attrNames (builtins.removeAttrs result (lib.attrNames kindDefaults));
    in
    if unknown == [ ] then
      kindDefaults // result
    else
      throw "sing-box kind '${inst.kind}' returns unknown fields: ${toString unknown}";

  results = lib.mapAttrs kindResult instances;
  resultList = lib.attrValues results;

  mkService =
    name: inst:
    let
      kind = results.${name};
      deps = [ "network-online.target" ] ++ kind.deps;
    in
    lib.nameValuePair "sing-box-${name}" {
      description = "sing-box instance '${name}' [${inst.kind}] (${toString (builtins.length inst.proxyDomains)} domains -> port ${toString inst.listenPort})";
      # wants, not bindsTo: a tunnel restart must not take the proxy down;
      # sing-box binds every new socket to the interface again.
      wants = deps;
      after = deps;
      wantedBy = [ "multi-user.target" ];
      inherit (kind) restartTriggers;
      environment = {
        SING_BOX_KIND = inst.kind;
        SING_BOX_OUT_FILE = "/run/sing-box/${name}/config.json";
        SING_BOX_LISTEN_ADDRESS = inst.listenAddress;
        SING_BOX_LISTEN_PORT = toString inst.listenPort;
        SING_BOX_PROXY_DOMAINS = builtins.toJSON inst.proxyDomains;
        SING_BOX_ROUTE_MATCH = inst.routeMatch;
      }
      // kind.environment;
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
          "${python} ${generator}/generate-config.py"
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
      // kind.serviceConfig;
    };

  exitInstances = lib.filterAttrs (_: i: i.exitNode or false) instances;

  # Values a kind claims (interface, table) must differ between all instances.
  claims = lib.zipAttrsWith (_: lib.concatLists) (map (r: r.claims) resultList);
  unitNames = lib.concatMap (r: lib.attrNames r.services) resultList;
  timerNames = lib.concatMap (r: lib.attrNames r.timers) resultList;

  commonAssertions =
    let
      each = pred: lib.filterAttrs (_: i: !pred i) instances;
      bad = lib.attrNames;
    in
    [
      {
        assertion = allUnique ports;
        message = "sing-box.nix: listenPort must differ between instances, got ${toString ports}";
      }
      {
        assertion = allUnique (unitNames ++ map (n: "sing-box-${n}") (lib.attrNames instances));
        message = "sing-box.nix: two instances define the same systemd unit";
      }
      {
        assertion = allUnique timerNames;
        message = "sing-box.nix: two instances define the same systemd timer";
      }
      {
        assertion = lib.all (n: (builtins.match "[a-z][a-z0-9_-]*" n) != null) (lib.attrNames instances);
        message = "sing-box.nix: instance names must match [a-z][a-z0-9_-]*, got ${toString (lib.attrNames instances)}";
      }
      {
        assertion = each (i: i.proxyDomains != [ ]) == { };
        message = "sing-box.nix: proxyDomains is empty in ${
          toString (bad (each (i: i.proxyDomains != [ ])))
        }";
      }
      {
        assertion =
          each (
            i:
            builtins.elem i.routeMatch [
              "domain"
              "domain_suffix"
            ]
          ) == { };
        message = "sing-box.nix: routeMatch must be domain or domain_suffix";
      }
      {
        assertion = each (i: lib.hasPrefix "/etc/" i.credentialFile) == { };
        message = "sing-box.nix: credentialFile must be under /etc/";
      }
      {
        assertion = lib.length (lib.attrNames exitInstances) <= 1;
        message = "sing-box.nix: at most one instance may set exitNode, got ${toString (lib.attrNames exitInstances)}";
      }
      {
        assertion = lib.all (n: results.${n}.exitTunnel != null) (lib.attrNames exitInstances);
        message = "sing-box.nix: exitNode is set on an instance whose kind owns no kernel interface: ${
          toString (lib.attrNames (lib.filterAttrs (n: _: results.${n}.exitTunnel == null) exitInstances))
        }";
      }
    ]
    ++ lib.mapAttrsToList (claim: values: {
      assertion = allUnique values;
      message = "sing-box.nix: ${claim} must differ between instances, got ${toString values}";
    }) claims
    ++ lib.concatMap (r: r.assertions) resultList;
in
{
  options.services.sing-box-tunnels.exitTunnel = lib.mkOption {
    type = lib.types.nullOr (
      lib.types.submodule {
        options = {
          interface = lib.mkOption { type = lib.types.str; };
          table = lib.mkOption { type = lib.types.int; };
        };
      }
    );
    readOnly = true;
    internal = true;
    description = "Interface and routing table of the tunnel that carries Tailscale exit-node traffic, or null.";
  };

  config = lib.mkMerge (
    [
      {
        assertions = commonAssertions;

        services.sing-box-tunnels.exitTunnel =
          if exitInstances == { } then null else results.${lib.head (lib.attrNames exitInstances)}.exitTunnel;

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

        # A tunnel that fails to come up would otherwise only reach the journal.
        services.failure-notify.units = lib.concatMap (r: r.failureUnits) resultList;

        systemd.services = lib.mkMerge (
          [ (lib.mapAttrs' mkService instances) ] ++ map (r: r.services) resultList
        );

        systemd.timers = lib.mkMerge (map (r: r.timers) resultList);

        # vless-<name>.age: link, subscription URL or vpn:// string; awg-<name>.age: AmneziaWG .conf or vpn:// string
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
    ]
    ++ map (r: r.extraConfig) resultList
  );
}
