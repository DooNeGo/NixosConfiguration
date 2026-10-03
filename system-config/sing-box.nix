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
  # Use the nixpkgs NixOS module (provides the sing-box user/group, polkit/
  # dbus wiring and default unit config). `settings` deliberately stays {}
  # so the module does NOT install its own ExecStartPre — our generator
  # below stays the only config producer.
  services.sing-box.enable = true;

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
    # wantedBy = [ "multi-user.target" ] is already set by
    # services.sing-box.enable — do not duplicate it.
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];

    environment.SING_BOX_PROXY_DOMAINS = builtins.toJSON proxyDomains;

    serviceConfig = {
      Type = "simple";
      RuntimeDirectory = "sing-box";
      RuntimeDirectoryMode = "0700";
      ExecStartPre = "${pkgs.python3}/bin/python3 ${generator}";
      # The module also defines ExecStart; systemd forbids a second ExecStart
      # via drop-in unless the value is first RESET with an empty assignment
      # (plain mkForce produced "more than one ExecStart=", unit bad-setting).
      ExecStart = [
        ""
        "${pkgs.sing-box}/bin/sing-box run -c /run/sing-box/config.json"
      ];
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

  # agenix (stage A): the VLESS credential is published to this PUBLIC repo as
  # an age-encrypted file instead of living only outside the Nix store.
  # Decryption happens at activation time using age.identityPaths (default on
  # this host: the sshd host keys, i.e. /etc/ssh/ssh_host_ed25519_key and
  # /etc/ssh/ssh_host_rsa_key).
  #
  # KEEP enable = false; until secrets/vless-key.age REALLY exists: the file
  # below is not present yet, and a placeholder must never be created — it
  # would be decrypted over the real key. Importing the agenix module with no
  # enabled secrets is safe (age.enable defaults to false then).
  #
  # --- activation steps (run as the repo user, repo root) ------------------
  # 1) one-time rules file with PUBLIC keys (recipients), create at repo root
  #    as secrets.nix:
  #      let
  #        user = "<contents of ~/.ssh/id_ed25519.pub>";
  #        host = "<contents of /etc/ssh/ssh_host_ed25519_key.pub>";
  #      in { "secrets/vless-key.age".publicKeys = [ user host ]; }
  #    (public keys only — reading/printing them is fine; never touch *.pub's
  #     private counterparts)
  # 2) create the encrypted secret ($EDITOR opens; paste the vless:// link or
  #    subscription URL and save):
  #      cd /home/openclaw/NixosConfiguration
  #      nix run github:ryantm/agenix/0.18.0 -- -e secrets/vless-key.age
  #    (our flake does not re-export the CLI, so run it from the pinned
  #     github ref; the source is already in the store after `nix flake lock`)
  #    If STDIN is non-interactive, $EDITOR is auto-set — alternatively:
  #      printf '%s\n' '<vless link or subscription URL>' | nix run github:ryantm/agenix/0.18.0 -- -e secrets/vless-key.age
  # 3) git add secrets/vless-key.age secrets.nix — the flake only sees tracked
  #    files, the build fails otherwise;
  # 4) flip enable = false; below to enable = true;
  # 5) sudo nixos-rebuild switch
  age.secrets.vless-key = {
    enable = false;
    file = ./secrets/vless-key.age;
    path = "/etc/sing-box/vless-key";
  };
}
