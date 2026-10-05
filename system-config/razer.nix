{ pkgs, ... }: {
  environment.systemPackages = with pkgs; [
    openrazer-daemon
  ];

  hardware.openrazer = {
    enable = true;
    users = [ "mathew" ];
  };
}
