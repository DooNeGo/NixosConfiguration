{ pkgs, ... }: {
  programs = {
    steam = {
      enable = true;
      remotePlay.openFirewall = true;
      gamescopeSession = {
        enable = true;
        args = [
          "-W 2560"
          "-H 1440"
          "-r 180"
          "--hdr-enabled"
        ];
      };
      extraCompatPackages = with pkgs; [ proton-ge-bin ];
      package = pkgs.steam.override {
        extraEnv = {
          MANGOHUD = "1";
          PULSE_SINK = "effect_input.spatializer71";
          PROTON_DLSS_UPGRADE = "1";
        };
      };
    };

    gamescope = {
      enable = true;
      capSysNice = true;
    };
  };

  environment.systemPackages = with pkgs; [
    gamescope-wsi
  ];
}
