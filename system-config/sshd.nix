{
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "no";
  };
  systemd.services.sshd.serviceConfig.OOMScoreAdjust = -1000;
}
