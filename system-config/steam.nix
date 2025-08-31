{ pkgs, ... }: {
  programs = {
    steam = {
      enable = true;
      gamescopeSession.enable = true;
      extraCompatPackages = with pkgs; [ proton-ge-bin ];
    };

    gamescope = {
      enable = true;
       capSysNice = true;
    };
  };
}
