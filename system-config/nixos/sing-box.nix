{
  config,
  pkgs,
  lib,
  ...
}:

let
  # Instance definitions: the one attrset to edit. evalModules gives them the
  # types and defaults below without making this module's config depend on itself.
  instances =
    (lib.evalModules {
      modules = [
        {
          options.instances = lib.mkOption { type = lib.types.attrsOf (lib.types.submodule instanceModule); };
        }
        {
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
              tun = {
                address = "172.19.0.1/30";
                fakeRange = "198.18.0.0/16";
              };
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
              proxyDomains = [
                "gitlab.credits.com"
                "mobileapi-stage.credits.com"
                "chats-stage.credits.com"
                "web-wallet-stage.credits.com"
              ];
              routeMatch = "domain_suffix";
              tun = {
                address = "172.19.0.5/30";
                fakeRange = "198.19.0.0/16";
              };
              vless = {
                runtimeKey = "/etc/sing-box/credits-key";
                fetchIntervalSec = 21600;
                onBootSec = "2min";
              };
            };
          };
        }
      ];
    }).config.instances;

  # Instance that HTTP(S)_PROXY points at.
  systemProxy = "main";

  instanceModule = {
    options = {
      kind = lib.mkOption {
        type = lib.types.enum (lib.attrNames kindFiles);
        description = "Tunnel kind: the file sing-box/kinds/<kind>.nix.";
      };
      listenAddress = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
      };
      listenPort = lib.mkOption { type = lib.types.port; };
      credentialFile = lib.mkOption {
        type = lib.types.strMatching "/etc/.+";
        description = "Where agenix delivers the credential: vless:// link, subscription URL, AmneziaWG .conf or Amnezia vpn:// string.";
      };
      proxyDomains = lib.mkOption { type = lib.types.nonEmptyListOf lib.types.str; };
      routeMatch = lib.mkOption {
        type = lib.types.enum [
          "domain"
          "domain_suffix"
        ];
      };
      exitNode = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "The Tailscale exit node forwards into this instance's tunnel (kinds that own an interface; at most one instance).";
      };
      tun = lib.mkOption {
        description = ''
          Fake-IP TUN next to the proxy port: programs that ignore HTTP(S)_PROXY reach proxyDomains through the tunnel.
          systemd-networkd owns the persistent link, its fake-IP route and the resolved routing domains; with sing-box down the names do not resolve.
        '';
        default = null;
        type = lib.types.nullOr (
          lib.types.submodule {
            options = {
              address = lib.mkOption {
                type = lib.types.strMatching "${ipv4}/30";
                description = "Address of the link with its /30 prefix, host .1 or .2 of its block; the other host is where sing-box answers DNS for resolved.";
              };
              fakeRange = lib.mkOption {
                type = lib.types.strMatching "${ipv4}/(8|9|1[0-9]|2[0-4])";
                description = "IPv4 range of the fake addresses; routed to the link.";
              };
            };
          }
        );
      };
      awg = lib.mkOption {
        description = "Settings of kind awg: the interface and routing table that wg-quick brings up.";
        default = { };
        type = lib.types.submodule {
          options = {
            interface = lib.mkOption {
              # kernel limit: interface names are at most 15 characters
              type = lib.types.strMatching "[a-z][a-z0-9]{0,14}";
            };
            table = lib.mkOption {
              # 0 and 253-255 are reserved, 52 is Tailscale's table
              type = lib.types.ints.between 256 2147483647;
            };
          };
        };
      };
      vless = lib.mkOption {
        description = "Settings of kind vless: the -fetch oneshot that resolves the credential into runtimeKey.";
        default = { };
        type = lib.types.submodule {
          options = {
            runtimeKey = lib.mkOption { type = lib.types.strMatching "/etc/.+"; };
            fetchIntervalSec = lib.mkOption {
              type = lib.types.ints.positive;
              default = 21600;
            };
            onBootSec = lib.mkOption {
              type = lib.types.str;
              default = "2min";
            };
          };
        };
      };
    };
  };

  ipv4 =
    let
      octet = "(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])";
    in
    lib.concatStringsSep "\\." (lib.replicate 4 octet);

  python = "${pkgs.python3}/bin/python3";

  waitLink = pkgs.writeShellApplication {
    name = "sing-box-wait-link";
    text = builtins.readFile ./sing-box/wait-link.sh;
    runtimeInputs = with pkgs; [ coreutils ];
  };

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
  otherTunDomains = lib.concatMap (inst: inst.proxyDomains) (
    lib.attrValues (builtins.removeAttrs tunInstances [ systemProxy ])
  );
  noProxy = lib.concatStringsSep "," (
    [ "localhost,127.0.0.1,::1,100.64.0.0/10,.ts.net,192.168.0.0/16,10.0.0.0/8" ] ++ otherTunDomains
  );

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
      result = import kindFiles.${inst.kind} {
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
      // lib.optionalAttrs (inst.tun != null) {
        SING_BOX_TUN = builtins.toJSON (tunFull name inst);
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
        ExecStartPre =
          lib.optional (inst.tun != null) "${waitLink}/bin/sing-box-wait-link ${tunLink name}"
          ++ [
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
      // lib.optionalAttrs (inst.tun != null) {
        # attaching to the persistent link and setting its address needs CAP_NET_ADMIN
        AmbientCapabilities = [ "CAP_NET_ADMIN" ];
        CapabilityBoundingSet = [ "CAP_NET_ADMIN" ];
      }
      // kind.serviceConfig;
    };

  tunInstances = lib.filterAttrs (_: i: i.tun != null) instances;
  tunLink = name: "sbtun-${name}";
  tunAddr = t: lib.head (lib.splitString "/" t.address);
  tunHost = t: lib.toInt (lib.last (lib.splitString "." (tunAddr t)));
  # the other host of the /30 block of the link address
  tunDns =
    t:
    let
      octets = lib.splitString "." (tunAddr t);
      last = tunHost t;
    in
    lib.concatStringsSep "." (
      lib.take 3 octets ++ [ (toString (if lib.mod last 4 == 1 then last + 1 else last - 1)) ]
    );
  tunFull =
    name: inst:
    inst.tun
    // {
      interface = tunLink name;
      dnsAddress = tunDns inst.tun;
    };
  # one unit file name per link, shared by the netdev and the network
  byLink =
    f: lib.mapAttrs' (name: inst: lib.nameValuePair "40-${tunLink name}" (f name inst)) tunInstances;
  tuns = lib.mapAttrsToList (_: i: i.tun) tunInstances;

  exitInstances = lib.filterAttrs (_: i: i.exitNode) instances;

  # Values a kind claims (interface, table) must differ between all instances.
  claims = lib.zipAttrsWith (_: lib.concatLists) (map (r: r.claims) resultList);
  unitNames = lib.concatMap (r: lib.attrNames r.services) resultList;
  timerNames = lib.concatMap (r: lib.attrNames r.timers) resultList;

  commonAssertions = [
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
      assertion = lib.length (lib.attrNames exitInstances) <= 1;
      message = "sing-box.nix: at most one instance may set exitNode, got ${toString (lib.attrNames exitInstances)}";
    }
    {
      assertion = lib.all (n: results.${n}.exitTunnel != null) (lib.attrNames exitInstances);
      message = "sing-box.nix: exitNode is set on an instance whose kind owns no kernel interface: ${
        toString (lib.attrNames (lib.filterAttrs (n: _: results.${n}.exitTunnel == null) exitInstances))
      }";
    }
    {
      assertion =
        allUnique (map tunAddr tuns ++ map tunDns tuns) && allUnique (map (t: t.fakeRange) tuns);
      message = "sing-box.nix: tun /30 blocks and fakeRange must differ between instances";
    }
    {
      # .0 and .3 of a /30 are the network and the broadcast address
      assertion = lib.all (t: lib.mod (tunHost t) 4 == 1 || lib.mod (tunHost t) 4 == 2) tuns;
      message = "sing-box.nix: a tun address must be host .1 or .2 of its /30 block";
    }
    {
      # resolved sends every subdomain of a proxied name to the TUN DNS; one that stayed direct would resolve back into the fake range
      assertion = lib.all (i: i.routeMatch == "domain_suffix") (lib.attrValues tunInstances);
      message = "sing-box.nix: an instance with tun needs routeMatch = \"domain_suffix\"";
    }
    {
      # kernel limit on link names
      assertion = lib.all (n: lib.stringLength (tunLink n) <= 15) (lib.attrNames tunInstances);
      message = "sing-box.nix: the link name sbtun-<name> is at most 15 characters, got ${toString (lib.attrNames tunInstances)}";
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

  options.services.sing-box-tunnels.fakeRanges = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    readOnly = true;
    internal = true;
    description = "Fake-IP ranges of the instances with a tun; the exit-node traffic to them must reach sing-box.";
  };

  config = lib.mkMerge (
    [
      {
        assertions = commonAssertions;

        services = {
          sing-box-tunnels = {
            fakeRanges = map (t: t.fakeRange) tuns;
            exitTunnel =
              if exitInstances == { } then null else results.${lib.head (lib.attrNames exitInstances)}.exitTunnel;
          };

          # A tunnel that fails to come up would otherwise only reach the journal.
          failure-notify.units = lib.concatMap (r: r.failureUnits) resultList;
        };

        users.users."sing-box" = {
          isSystemUser = true;
          group = "sing-box";
          home = "/var/lib/sing-box";
        };
        users.groups."sing-box" = { };

        environment = {
          systemPackages = [ pkgs.sing-box ];

          variables = {
            HTTP_PROXY = proxyUrl;
            HTTPS_PROXY = proxyUrl;
            NO_PROXY = noProxy;
            http_proxy = proxyUrl;
            https_proxy = proxyUrl;
            no_proxy = noProxy;
          };

          # Browser DoH bypasses the system resolver, so the fake addresses would never reach the browser.
          # Firefox reads /etc/firefox/policies/policies.json, Google Chrome /etc/opt/chrome/policies/managed.
          etc = lib.mkIf (tunInstances != { }) {
            "firefox/policies/policies.json".text = builtins.toJSON {
              policies.DNSOverHTTPS = {
                Enabled = false;
                Locked = true;
              };
            };
            "opt/chrome/policies/managed/dns.json".text = builtins.toJSON { DnsOverHttpsMode = "off"; };
          };
        };

        # sing-box redirects each TCP connection to a listener on the link address; the firewall drops that input otherwise
        networking.firewall.trustedInterfaces = map tunLink (lib.attrNames tunInstances);

        systemd = {
          services = lib.mkMerge ([ (lib.mapAttrs' mkService instances) ] ++ map (r: r.services) resultList);

          timers = lib.mkMerge (map (r: r.timers) resultList);

          network.netdevs = byLink (
            name: _: {
              netdevConfig = {
                Kind = "tun";
                Name = tunLink name;
              };
              tunConfig = {
                User = "sing-box";
                Group = "sing-box";
              };
            }
          );

          network.networks = byLink (
            name: inst: {
              matchConfig.Name = tunLink name;
              address = [ inst.tun.address ];
              routes = [ { Destination = inst.tun.fakeRange; } ];
              dns = [ (tunDns inst.tun) ];
              domains = map (d: "~${d}") inst.proxyDomains;
              networkConfig.ConfigureWithoutCarrier = true;
              linkConfig.RequiredForOnline = "no";
            }
          );
        };

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
