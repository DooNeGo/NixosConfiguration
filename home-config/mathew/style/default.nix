# The look of the desktop in one place: fonts, the "glass" surface, corners, gaps and the contrast of the palette.
# `tokens` are the `@name@` placeholders of the style files; `subst` fills them in, so a template, a CSS, a theme or a
# Lua file carries the token instead of its own copy of the number. Consumers: `waybar.nix`, `rofi.nix`, `mako.nix`,
# `hyprlock.nix`, `kitty.nix`, `hyprland.nix` (the Lua files) and `wallpaper/palettes.nix` (the matugen templates).
# Colours themselves are not here: they come from the wallpaper palette under their matugen names, and each style
# file picks the ones it needs.
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
  fontFamily = "JetBrainsMono Nerd Font";

  # Two fill opacities, the same in both modes: a window (the terminal, every layer of the file manager) and a floating
  # panel (the bar islands, the launcher, notifications, the lock field). The panels are the thinner glass, the
  # windows hold more text and need the denser fill.
  windowAlpha = 0.8;
  panelAlpha = 0.5;
  borderWidth = 1;
  borderAlpha = 0.28;
  blurPasses = 3;

  paletteContrast = 0.0;

  # The only choice that depends on the mode, used by the terminal palette (palette/kitty.conf): black stays dark
  # and white light in both modes, so a program that prints "black" stays readable. Values are matugen colour names.
  ansi = {
    dark = {
      black = "surface_container_highest";
      white = "on_surface_variant";
      brightWhite = "on_surface";
    };
    light = {
      black = "on_surface";
      white = "surface_container_highest";
      brightWhite = "surface_container_lowest";
    };
  };
  # Layer namespaces that get the blur rule (hyprland/rules.lua).
  glassLayers = [
    "waybar"
    "notifications"
    "rofi"
  ];

  # Corners: a panel, an element inside a panel (a workspace button, the selected launcher row) and a window.
  radius = 20;
  radiusInner = 12;
  radiusWindow = 15;

  # Gaps between windows and panels, and the space inside the small ones.
  gap = 10;
  gapInner = 5;

  tokens = {
    "@font_family@" = fontFamily;
    "@glass_border_alpha@" = toString borderAlpha;
    "@glass_border_alpha_hex@" = hex borderAlpha;
    "@glass_border_width@" = toString borderWidth;
    "@window_alpha@" = toString windowAlpha;
    "@panel_alpha@" = toString panelAlpha;
    "@panel_alpha_hex@" = hex panelAlpha;
    "@blur_passes@" = toString blurPasses;
    "@glass_layers@" = lib.concatMapStringsSep ", " (n: ''"${n}"'') glassLayers;
    "@radius@" = toString radius;
    "@radius_inner@" = toString radiusInner;
    "@radius_window@" = toString radiusWindow;
    "@gap@" = toString gap;
    "@gap_inner@" = toString gapInner;
  };

  # The tokens that depend on the mode.
  modeTokens = mode: {
    "@ansi_black@" = ansi.${mode}.black;
    "@ansi_white@" = ansi.${mode}.white;
    "@ansi_bright_white@" = ansi.${mode}.brightWhite;
  };

  # Fills the tokens of a text and fails the build on a `@name@` that is left over (a typo or a missing token); a
  # caller fills its own placeholders before calling. `subst` knows only the tokens that do not depend on the mode:
  # a file that needs the others is a palette template (`substMode`), which wallpaper/palettes.nix renders once for
  # each mode.
  substWith =
    toks: text:
    let
      out = builtins.replaceStrings (lib.attrNames toks) (lib.attrValues toks) text;
      left = lib.unique (
        map builtins.head (lib.filter builtins.isList (builtins.split "(@[a-z_]+@)" out))
      );
    in
    if left == [ ] then out else throw "style: unknown token ${lib.concatStringsSep ", " left}";
  subst = substWith tokens;
  substMode = mode: substWith (tokens // modeTokens mode);
}
