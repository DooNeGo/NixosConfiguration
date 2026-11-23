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
  # over a blurred background with a thin light border.
  alpha = 0.3;
  borderAlpha = 0.16;
  borderWidth = 1;
  # GTK file manager (gtk.nix): a file list needs more fill than a panel to stay readable over the blur, while the
  # window background and the toolbars stay close to the panels.
  glassViewAlpha = 0.6;
  glassChromeAlpha = 0.6;
  blurPasses = 3;
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
    "@glass_alpha@" = toString alpha;
    "@glass_alpha_hex@" = hex alpha;
    "@glass_border_alpha@" = toString borderAlpha;
    "@glass_border_hex@" = hex borderAlpha;
    "@glass_border_width@" = toString borderWidth;
    "@glass_view_alpha@" = toString glassViewAlpha;
    "@glass_chrome_alpha@" = toString glassChromeAlpha;
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

  # Fills the tokens of a text and fails the build on a `@name@` that is left over (a typo or a missing token); a
  # caller fills its own placeholders before calling.
  subst =
    text:
    let
      out = builtins.replaceStrings (lib.attrNames tokens) (lib.attrValues tokens) text;
      left = lib.unique (
        map builtins.head (lib.filter builtins.isList (builtins.split "(@[a-z_]+@)" out))
      );
    in
    if left == [ ] then out else throw "style: unknown token ${lib.concatStringsSep ", " left}";
}
