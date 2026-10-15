{
  imports = [
    ../shared/git.nix
  ];

  programs.git = {
    settings = {
      user = {
        email = "matveyprostomac@gmail.com";
        name = "Mathew Kastrama";
      };
    };
  };
}
