{
  services.openssh = {
    enable = true;
    settings = {
      MaxSessions = 1;
    };
  };
}
