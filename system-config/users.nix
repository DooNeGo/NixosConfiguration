{ pkgs, ... }: {
  users.users.mathew = {
    isNormalUser = true;
    description = "Default user for desktop";
    hashedPassword = "$y$j9T$qEa6nXlqe74ZWOuYHsLN..$cym2MjTNePrMhkWvm9bI.7zsJeLj8XpqfZjuaVfD9Q/";
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
