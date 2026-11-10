# One configured vim for every user and for root. Built as a package because the programs.vim options of NixOS
# and nix-darwin have nothing in common.
{ pkgs, lib, ... }:
let
  vim = pkgs.vim-full.customize {
    vimrcConfig = {
      packages.shared.start = [
        pkgs.vimPlugins.vim-sensible
      ]
      ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
        pkgs.vimPlugins.vim-wayland-clipboard
      ];
      customRC = ''
        " `-` = anonymous stdin; a bare nixfmt call prints a deprecation warning that would end up in the buffer.
        let g:nixfmt = '${pkgs.nixfmt}/bin/nixfmt -'
        ${builtins.readFile ./vim/vimrc}
      '';
    };
  };
in
{
  environment = {
    systemPackages = [ vim ];
    variables.EDITOR = "vim";
  };
}
