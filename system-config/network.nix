{
  networking.useNetworkd = true;

  systemd.network = {
    enable = true;
    wait-online.enable = false;
  };
}
