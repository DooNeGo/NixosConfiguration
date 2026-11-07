{ config, ... }: {
  age.secrets.murmur-password.file = ../secrets/murmur-password.age;

  services.murmur = {
    enable = true;
    bandwidth = 540000;
    bonjour = true;
    environmentFile = config.age.secrets.murmur-password.path;
    password = "$MURMURD_PASSWORD";
    autobanTime = 0;
    openFirewall = true;
  };
}
