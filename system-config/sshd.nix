{
  services.openssh.enable = true;
  systemd.services.sshd.serviceConfig.OOMScoreAdjust = -1000;
}
