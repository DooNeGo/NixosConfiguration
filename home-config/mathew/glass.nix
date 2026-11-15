# The "glass" surface shared by the bar islands, notifications, the lock screen field and the launcher: a translucent
# fill over a blurred background with a 1 px light border. One place for its numbers; the consumers are
# `waybar.nix` (CSS), `wallpaper/` (palette templates) and `hyprland/rules.lua` (blur rules).
lib:
let
  hex =
    a:
    let
      n = builtins.floor (a * 255 + 0.5);
    in
    (if n < 16 then "0" else "") + lib.toLower (lib.toHexString n);
in
rec {
  alpha = 0.3;
  borderAlpha = 0.16;
  alphaHex = hex alpha;
  borderHex = hex borderAlpha;
}
