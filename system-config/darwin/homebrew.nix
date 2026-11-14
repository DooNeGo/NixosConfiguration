{
  config,
  inputs,
  user,
  ...
}:
{
  imports = [ inputs.nix-homebrew.darwinModules.nix-homebrew ];

  nix-homebrew = {
    enable = true;
    enableRosetta = false;
    inherit user;
    autoMigrate = true;
    taps."homebrew/homebrew-core" = inputs.homebrew-core;
    taps."homebrew/homebrew-cask" = inputs.homebrew-cask;
    mutableTaps = false;
  };

  homebrew = {
    enable = true;
    inherit user;
    onActivation.cleanup = "uninstall";
    taps = builtins.attrNames config.nix-homebrew.taps;
    casks = [ ];
  };
}
