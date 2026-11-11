{ pkgs, lib, ... }:
let
  dotnet = pkgs.dotnet-sdk_10;
  environment.DOTNET_ROOT = "${dotnet}/share/dotnet";
in
{
  systemd.user.sessionVariables = lib.mkIf pkgs.stdenv.hostPlatform.isLinux environment;

  home = {
    packages = [ dotnet ];
    sessionVariables = environment // {
      PATH = "${dotnet}/bin:$PATH";
    };
  };
}
