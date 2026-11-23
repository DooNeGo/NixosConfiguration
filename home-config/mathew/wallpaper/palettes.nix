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
  # Green and yellow keep their own hue (`blend = false`): blended towards the wallpaper, a yellow turned olive and
  # a green turned teal. Red is the Material error colour.
  matugenConfig =
    mode:
    pkgs.writeText "matugen-${mode}.toml" (
      ''
        [config]
        [config.custom_colors.green]
        color = "#50fa7b"
        blend = false
        [config.custom_colors.yellow]
        color = "#f1fa8c"
        blend = false
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

  # One directory per image with one per mode. --source-color-index picks the colour without asking on a terminal. A
  # palette that misses a file or whose contrast leaves its band (contrast.py) fails the build: a consumer would
  # otherwise start without its include, or a new wallpaper would make the desktop hard to read.
  palettes =
    pkgs.runCommand "wallpaper-palettes"
      {
        nativeBuildInputs = [
          pkgs.matugen
          pkgs.python3
        ];
      }
      ''
        export HOME=$TMPDIR
        render=$TMPDIR/render
        mkdir -p $out
        ${lib.concatMapStrings (
          m: "sed \"s|@out@|$render|\" ${matugenConfig m} > $TMPDIR/matugen-${m}.toml\n"
        ) modes}
        ${common.findImages} -print0 > $TMPDIR/images
        failed=
        while IFS= read -r -d "" img; do
          name=$(basename "$img")
          for mode in ${lib.concatStringsSep " " modes}; do
            case $mode in
              dark) kv=${kvantumRoot}/KvFlat/KvFlat ;;
              light) kv=${kvantumRoot}/KvFlatLight/KvFlatLight ;;
            esac
            rm -rf "$render"
            mkdir "$render"
            matugen -q -c $TMPDIR/matugen-$mode.toml -m $mode -t scheme-tonal-spot --source-color-index 0 image "$img"
            sed -f "$render/kvantum.sed" "$kv.kvconfig" > "$render/KvMatugen.kvconfig"
            sed -f "$render/kvantum.sed" "$kv.svg" > "$render/KvMatugen.svg"
            rm "$render/kvantum.sed"
            for f in ${lib.concatStringsSep " " files}; do
              [ -s "$render/$f" ] || { echo "matugen made no $f for $name ($mode)" >&2; exit 1; }
            done
            python3 -I ${./contrast.py} "$render" "$name ($mode)" || failed=1
            mkdir -p "$out/$name"
            mv "$render" "$out/$name/$mode"
          done
        done < $TMPDIR/images
        [ -z "$failed" ] || { echo "the contrast of a palette is outside its band (wallpaper/contrast.py)" >&2; exit 1; }
        [ -n "$(ls -A $out)" ] || { echo "no wallpaper image found" >&2; exit 1; }
      '';

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
