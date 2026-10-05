{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    paper-icon-theme
    paper-gtk-theme
  ];

  programs.dconf = {
    enable = true;
    profiles.user.databases = [
      {
        settings."org/gnome/desktop/interface" = {
          gtk-theme = "Paper";
          icon-theme = "Paper-Mono-Dark";
          font-name = "Noto Sans Medium 11";
          document-font-name = "Noto Sans Medium 11";
          monospace-font-name = "Noto Sans Mono Medium 11";
        };
      }
    ];
  };
}
