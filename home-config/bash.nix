{ config, nix-colors, pkgs, ... }:
let
  contrib = nix-colors.lib.contrib { inherit pkgs; };
  initShellColorsScript = contrib.shellThemeFromScheme {
    scheme = config.colorScheme;
  };
in {
  programs.bash = {
    enable = true;
    initExtra = "sh ${initShellColorsScript}";
  };
}
