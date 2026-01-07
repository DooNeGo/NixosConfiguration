{
  users.users.mathew = {
    isNormalUser = true;
    description = "mathew";
    extraGroups = [ "wheel" "input" "networkmanager" "doonego" ];
  };

  users.groups.doonego = {
    gid = 1000;
  };
}
