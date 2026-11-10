{ config, pkgs, ... }: {
  # agenix decrypts it before users are created, so hashedPasswordFile can use it.
  age.secrets.mathew-password.file = ../../secrets/mathew-password.age;

  users.users.mathew = {
    isNormalUser = true;
    description = "Default user for desktop";
    hashedPasswordFile = config.age.secrets.mathew-password.path;
    extraGroups = [
      "wheel"
      "input"
      "adbusers"
      "kvm"
      "audio"
      "wireshark"
    ];
    shell = pkgs.zsh;
  };

  users.users.openclaw-npm = {
    isNormalUser = true;
    linger = true;
    shell = pkgs.zsh;
    extraGroups = [ "systemd-journal" ]; # read-only access to the system/user journals for diagnostics
  };
}
