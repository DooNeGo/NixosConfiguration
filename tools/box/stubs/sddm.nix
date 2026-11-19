# The display manager of the owner's machine holds DRM master on a physical monitor; in the container nothing may
# need it, but units order after display-manager.service. This keeps that unit active and runs no display manager.
{ pkgs }:
let
  stub = pkgs.runCommand "sddm-stub" { } ''
    mkdir -p $out/bin $out/share/dbus-1 $out/lib/tmpfiles.d
    printf '#!${pkgs.runtimeShell}\nexec ${pkgs.coreutils}/bin/sleep infinity\n' > $out/bin/sddm
    chmod +x $out/bin/sddm
  '';
in
# The module calls `cfg.package.override`.
stub // { override = _: stub; }
