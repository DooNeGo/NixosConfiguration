{ config, pkgs, ... }:

let
  gitHost = "gitlab.credits.com";
  proxyPort = 2081;
in
{
  programs.git = {
    enable = true;
    settings.user = {
      email = "matveyprostomac@gmail.com";
      name = "Mathew Kastrama";
    };
  };

  home.packages = [ pkgs.libressl.nc ];

  home.file.".ssh/config.d/singbox-git.conf".text = ''
    Host ${gitHost}
        ProxyCommand ${pkgs.libressl.nc}/bin/nc -X connect -x 127.0.0.1:${toString proxyPort} %h %p
  '';

  # HTTPS per-URL proxy (unused while the operator clones via SSH):
  # programs.git.settings.include.path =
  #   "${config.home.homeDirectory}/.config/git/singbox-gitproxy.gitconfig";
  # home.file.".config/git/singbox-gitproxy.gitconfig".text = ''
  #   [http "https://${gitHost}"]
  #       proxy = http://127.0.0.1:${toString proxyPort}
  # '';
}
