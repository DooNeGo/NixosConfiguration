{ pkgs, ... }: {
  users.users.mathew = {
    isNormalUser = true;
    description = "Default user for desktop";
    hashedPassword = "$y$j9T$qEa6nXlqe74ZWOuYHsLN..$cym2MjTNePrMhkWvm9bI.7zsJeLj8XpqfZjuaVfD9Q/";
    extraGroups = [ "wheel" "input" "adbusers" "kvm" "audio"  ];
    shell = pkgs.zsh;
  };
}
