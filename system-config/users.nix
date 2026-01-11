{ pkgs, ... }: {
  users.users.mathew = {
    isNormalUser = true;
    description = "mathew";
    extraGroups = [ "wheel" "input" "adbusers" "kvm" "audio"  ];
    shell = pkgs.zsh;
  };

  users.groups.doonego = {
    gid = 1000;
  };
}
