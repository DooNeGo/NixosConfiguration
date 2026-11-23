# The look of the desktop in one place: fonts, the "glass" surface, corners, gaps and the palette roles that colour them.
# `tokens` are the `@name@` placeholders of the style files; `subst` fills them in, so a template, a CSS, a theme or a
# Lua file carries the token instead of its own copy of the number. Consumers: `waybar.nix`, `rofi.nix`, `mako.nix`,
# `hyprlock.nix`, `kitty.nix`, `hyprland.nix` (the Lua files) and `wallpaper/palettes.nix` (the matugen templates).
# Colours themselves are not here: they come from the wallpaper palette, and only the role names are fixed here.
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

  # The glass surface of the bar islands, notifications, the launcher panels and the lock field: a translucent fill
  # over a blurred background with a thin border. The fill alpha depends on the mode (`modes`).
  borderAlpha = 0.16;
  borderWidth = 1;
  blurPasses = 3;

  # What differs between the dark and the light palette. A light panel is mostly the wallpaper, so dark text on it
  # needs a denser fill than light text on a dark one. The `*Soften` values move the main text, the secondary text and
  # the accent colours (the accent and the ANSI hues of the terminal) along the lightness scale (matugen `lighten`,
  # percentage points of HSL lightness): the Material roles reach 14:1 to 16:1 for the text and 11:1 for the dark
  # accent, which is harsher than the band the palette check (wallpaper/contrast.py) holds them to (text 9 to 13,
  # secondary text 5.5 to 9, accent 4.5 to 9). The light accent is already near 6:1, so it is left alone.
  # `ansi` names the roles of the ANSI black and whites: black stays dark and white light in both modes, so a
  # program that prints "black" stays readable. Template tokens: `substMode`.
  modes = {
    dark = {
      glassAlpha = 0.3;
      # GTK file manager (gtk.nix): a file list needs more fill than a panel to stay readable over the blur, while the
      # window background and the toolbars stay close to the panels.
      glassViewAlpha = 0.6;
      glassChromeAlpha = 0.6;
      textSoften = -8;
      dimSoften = -15;
      accentSoften = -15;
      # The text on an accent fill darkens as the accent dims, to keep its contrast.
      onAccentSoften = -14;
      terminalOpacity = 0.65;
      viewBg = "surface";
      ansi = {
        black = "surface_container_highest";
        white = "on_surface_variant";
        brightWhite = "on_surface";
      };
    };
    light = {
      glassAlpha = 0.7;
      glassViewAlpha = 0.8;
      glassChromeAlpha = 0.7;
      textSoften = 12;
      dimSoften = 6;
      accentSoften = 0;
      onAccentSoften = 0;
      terminalOpacity = 0.85;
      # The big light areas (file list, text fields) one step below the brightest surface: less glare.
      viewBg = "surface_container_low";
      ansi = {
        black = "on_surface";
        white = "surface_container_highest";
        brightWhite = "surface_container_lowest";
      };
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

  # Material roles of the wallpaper palette (see wallpaper/palettes.nix) that colour each part.
  roles = {
    glassFill = "surface_container_high";
    glassBorder = "on_surface";
    text = "on_surface";
    textDim = "on_surface_variant";
    accent = "primary";
  };

  tokens = {
    "@font_family@" = fontFamily;
    "@glass_border_alpha@" = toString borderAlpha;
    "@glass_border_hex@" = hex borderAlpha;
    "@glass_border_width@" = toString borderWidth;
    "@blur_passes@" = toString blurPasses;
    "@glass_layers@" = lib.concatMapStringsSep ", " (n: ''"${n}"'') glassLayers;
    "@radius@" = toString radius;
    "@radius_inner@" = toString radiusInner;
    "@radius_window@" = toString radiusWindow;
    "@gap@" = toString gap;
    "@gap_inner@" = toString gapInner;
    "@role_glass_fill@" = roles.glassFill;
    "@role_glass_border@" = roles.glassBorder;
    "@role_text@" = roles.text;
    "@role_text_dim@" = roles.textDim;
    "@role_accent@" = roles.accent;
  };

  # The tokens that depend on the mode.
  modeTokens = mode: {
    "@glass_alpha@" = toString modes.${mode}.glassAlpha;
    "@glass_alpha_hex@" = hex modes.${mode}.glassAlpha;
    "@glass_view_alpha@" = toString modes.${mode}.glassViewAlpha;
    "@glass_chrome_alpha@" = toString modes.${mode}.glassChromeAlpha;
    "@text_soften@" = toString modes.${mode}.textSoften;
    "@dim_soften@" = toString modes.${mode}.dimSoften;
    "@accent_soften@" = toString modes.${mode}.accentSoften;
    "@on_accent_soften@" = toString modes.${mode}.onAccentSoften;
    "@role_view_bg@" = modes.${mode}.viewBg;
    "@role_ansi_black@" = modes.${mode}.ansi.black;
    "@role_ansi_white@" = modes.${mode}.ansi.white;
    "@role_ansi_bright_white@" = modes.${mode}.ansi.brightWhite;
    "@terminal_opacity@" = toString modes.${mode}.terminalOpacity;
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
