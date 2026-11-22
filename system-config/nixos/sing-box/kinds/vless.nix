# kind = "vless": credentialFile holds a vless:// link, a subscription URL or an
# Amnezia vpn:// string with an xray container; the -fetch oneshot and its timer
# resolve it into runtimeKey, which sing-box reads through LoadCredential.
{
  pkgs,
  name,
  inst,
  shared,
  ...
}:

let
  vlessFetch = pkgs.writeShellApplication {
    name = "sing-box-vless-fetch";
    text = builtins.readFile ./vless-fetch.sh;
    runtimeInputs = with pkgs; [
      curl
      coreutils
      gnused
      gnugrep
      python3
    ];
  };

  fetch = "sing-box-${name}-fetch";
in
{
  services.${fetch} = {
    description = "Resolve sing-box credential for instance '${name}' into the runtime key";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    environment = {
      SING_BOX_VLESS_CREDENTIAL_FILE = inst.credentialFile;
      SING_BOX_VLESS_KEY_FILE = inst.vless.runtimeKey;
      SING_BOX_DECODE_VPN = "${shared.decodeVpn}";
    };
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStart = "${vlessFetch}/bin/sing-box-vless-fetch";
    };
  };

  timers.${fetch} = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = inst.vless.onBootSec;
      OnUnitActiveSec = toString inst.vless.fetchIntervalSec;
      Unit = "${fetch}.service";
    };
  };

  deps = [ "${fetch}.service" ];

  environment = {
    SING_BOX_VLESS_CREDENTIAL = "${name}-key";
    SING_BOX_VLESS_TRANSPORT_OVERRIDE = "";
  };

  failureUnits = [ fetch ];

  serviceConfig.LoadCredential = "${name}-key:${inst.vless.runtimeKey}";
}
