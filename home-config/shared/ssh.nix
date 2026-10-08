{ pkgs, lib, ... }:

let
  gitHost = "gitlab.credits.com";
  proxyPort = 2081;
in
{
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    settings = {
      ${gitHost} = {
        host = gitHost;
        user = "git";
        proxyCommand = "${pkgs.libressl.nc}/bin/nc -X connect -x 127.0.0.1:${toString proxyPort} %h %p";
      };
    };
  };

  home = {
    packages = [ pkgs.libressl.nc ];
    file.".ssh/config".force = true;
    activation = {
      # https://github.com/nix-community/home-manager/issues/322
      fixSshPermissions = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
        run install -d -m 0700 "$HOME/.ssh"
        if [ -L "$HOME/.ssh/config" ]; then
          src="$(readlink -f "$HOME/.ssh/config")"
          run rm -f "$HOME/.ssh/config"
          run install -m 0600 "$src" "$HOME/.ssh/config"
        fi
      '';
    };
  };
}
