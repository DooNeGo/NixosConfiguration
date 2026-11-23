# The palettes of every wallpaper, rendered at build time: one directory per image and mode with one file per template.
{
  lib,
  pkgs,
  common,
}:
let
  style = import ../style lib;
  modes = [
    "dark"
    "light"
  ];

  # Templates in ../palette, one output name each; a consumer imports its file from the palette directory.
  templates = {
    waybar = "waybar.css";
    mako = "mako";
    kitty = "kitty.conf";
    hyprlock = "hyprlock.conf";
    rofi = "rofi.rasi";
    gtk = "gtk.css";
    yazi = "yazi.toml";
    glow = "glow.json";
  };
  # Kvantum: a sed script per mode recolours KvFlat (dark) or KvFlatLight (light) into the two files of the theme
  # KvMatugen; the script itself is an intermediate and is not copied.
  kvantumFiles = [
    "KvMatugen.kvconfig"
    "KvMatugen.svg"
  ];
  kvantumRoot = "${pkgs.kdePackages.qtstyleplugin-kvantum}/share/Kvantum";
  files = lib.attrValues templates ++ kvantumFiles;

  # The style tokens (style/) are filled in before matugen renders the colours; the ones of the mode with them.
  template =
    mode: file:
    pkgs.writeText file (style.substMode mode (builtins.readFile (../palette + "/${file}")));
  kvantumSed =
    mode:
    pkgs.writeText "kvantum-${mode}.sed" (
      style.substMode mode (builtins.readFile ../palette/kvantum-${mode}.sed)
    );

  # @out@ is the render directory of the build script: a fixed path, so no wallpaper name is ever spliced into the file.
  # Green and yellow are custom colours harmonised to the wallpaper (`blend = true`); red is the Material error
  # colour. The softness of the whole palette is one matugen parameter, `--contrast` (style/).
  matugenConfig =
    mode:
    pkgs.writeText "matugen-${mode}.toml" (
      ''
        [config]
        [config.custom_colors.green]
        color = "#50fa7b"
        blend = true
        [config.custom_colors.yellow]
        color = "#f1fa8c"
        blend = true
        [templates.kvantum]
        input_path = "${kvantumSed mode}"
        output_path = "@out@/kvantum.sed"
      ''
      + lib.concatStrings (
        lib.mapAttrsToList (name: file: ''
          [templates.${name}]
          input_path = "${template mode file}"
          output_path = "@out@/${file}"
        '') templates
      )
    );

  # Independent derivations let Nix schedule renders using its configured build jobs.
  renderPalette =
    name: mode:
    let
      image = common.wallDir + "/${name}";
      stem = lib.removeSuffix ".${lib.last (lib.splitString "." name)}" name;
      kvTheme = if mode == "dark" then "KvFlat" else "KvFlatLight";
      kv = "${kvantumRoot}/${kvTheme}/${kvTheme}";
    in
    pkgs.runCommand (lib.strings.sanitizeDerivationName "palette-${stem}-${mode}")
      {
        nativeBuildInputs = [
          pkgs.matugen
          pkgs.python3
        ];
      }
      ''
        export HOME="$TMPDIR"
        mkdir -p "$out"
        sed "s|@out@|$out|" ${matugenConfig mode} > "$TMPDIR/matugen.toml"
        matugen -q -c "$TMPDIR/matugen.toml" -m ${mode} --contrast=${toString style.paletteContrast} -t scheme-tonal-spot --source-color-index 0 image ${lib.escapeShellArg "${image}"}
        sed -f "$out/kvantum.sed" "${kv}.kvconfig" > "$out/KvMatugen.kvconfig"
        sed -f "$out/kvantum.sed" "${kv}.svg" > "$out/KvMatugen.svg"
        rm "$out/kvantum.sed"
        for f in ${lib.concatStringsSep " " files}; do
          [ -s "$out/$f" ] || { echo "matugen made no $f" >&2; exit 1; }
        done
        python3 -I ${./contrast.py} "$out" ${lib.escapeShellArg "${name} (${mode})"}
      '';

  palettes = pkgs.linkFarm "wallpaper-palettes" (
    lib.concatMap (
      name:
      map (mode: {
        name = "${name}/${mode}";
        path = renderPalette name mode;
      }) modes
    ) images
  );

  images = lib.sort lib.lessThan (
    lib.filter (
      n:
      lib.any (s: lib.hasSuffix s (lib.toLower n)) [
        ".jpg"
        ".jpeg"
        ".png"
      ]
    ) (lib.attrNames (lib.filterAttrs (_: type: type == "regular") (builtins.readDir common.wallDir)))
  );
in
{
  inherit palettes files modes;

  # The palette that a fresh state directory starts with: the first wallpaper by name.
  defaultWallpaper =
    if images == [ ] then
      throw "assets/wallpapers has no .jpg, .jpeg or .png image"
    else
      lib.head images;
}
