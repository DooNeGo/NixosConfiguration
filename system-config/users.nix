{
  users.users.mathew = {
    isNormalUser = true;
    description = "mathew";
    extraGroups = [ "wheel" "input" ];
  };

  users.groups.doonego = {
    gid = 1000;
  };
}
