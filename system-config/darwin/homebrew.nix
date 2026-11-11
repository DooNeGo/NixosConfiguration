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
    taps."homebrew/homebrew-cask" = inputs.homebrew-cask;
    mutableTaps = false;
  };

  homebrew = {
    enable = true;
    inherit user;
    taps = builtins.attrNames config.nix-homebrew.taps;
    casks = [
      "xcodes-app"
      "microsoft-teams"
      "finetune"
    ];
  };
}
