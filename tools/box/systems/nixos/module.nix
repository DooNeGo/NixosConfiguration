{ lib, pkgs, ... }:
let
  # Not tested yet, and they need what the container lacks (a btrfs mount, a disk, the network, secrets). Each comes
  # back with the environment it needs when a change asks for it.
  disabledUnits = [
    "awg-exit-node"
    "tailscaled"
    "tailscaled-set"
    "tailscaled-serve"
    "tailscaled-autoconnect"
    "sing-box-credits-git-fetch"
    "sing-box-main-awg-prepare"
  ];
  # Hyprland refuses to run as root without a flag; start-hyprland passes what follows `--` on to Hyprland.
  wrapForRoot =
    p:
    pkgs.symlinkJoin {
      name = "${p.name}-root";
      inherit (p) version;
      meta = p.meta // {
        outputsToInstall = [ "out" ];
      };
      paths = [ p ];
      postBuild = ''
        rm $out/share/wayland-sessions/hyprland.desktop
        substitute ${p}/share/wayland-sessions/hyprland.desktop $out/share/wayland-sessions/hyprland.desktop \
          --replace-fail "Exec=${p}/bin/start-hyprland" "Exec=${p}/bin/start-hyprland -- --i-am-really-stupid"
      '';
      passthru = p.passthru // {
        override = lib.setFunctionArgs (a: wrapForRoot (p.override a)) (lib.functionArgs p.override);
      };
    };
  rootHyprland = wrapForRoot pkgs.hyprland;
in
{
  # What lib.sh and the checks of this layer use.
  environment.systemPackages = with pkgs; [
    grim
    imagemagick
    jq
  ];

  programs.hyprland.package = lib.mkForce rootHyprland;

  boot.kernel.sysfs = lib.mkForce { };
  # A user unit that needs a razer device.
  hardware.openrazer.enable = lib.mkForce false;
  networking = {
    firewall.enable = lib.mkForce false;
    nftables.enable = lib.mkForce false;
  };

  services = {
    # The container uses the host resolver, which resolved cannot run with.
    resolved.enable = lib.mkForce false;
    murmur.enable = lib.mkForce false;
    smartd.enable = lib.mkForce false;
    displayManager.sddm.package = lib.mkForce (import ../../stubs/sddm.nix { inherit pkgs; });
  };

  systemd = {
    services =
      lib.genAttrs disabledUnits (_: {
        enable = lib.mkForce false;
      })
      // {
        # The session runs as the container root: a container user cannot open /dev/dri/card0 (docs/box.md). The unit
        # keeps its own command; only the desktop entry that uwsm starts gets the flag Hyprland needs as root.
        hyprland-headless-mathew = {
          environment = {
            XDG_SESSION_CLASS = "user";
            XDG_RUNTIME_DIR = "/run/user/0";
            DBUS_SESSION_BUS_ADDRESS = "unix:path=/run/user/0/bus";
          };
          serviceConfig.User = lib.mkForce "root";
        };
      };
    # The document portal needs a FUSE mount that a rootless container cannot make.
    user.services.xdg-document-portal.enable = lib.mkForce false;
  };
}
