# The palettes of every wallpaper, rendered at build time: one directory per image with one file per template.
{
  lib,
  pkgs,
  common,
}:
let
  glass = import ../glass.nix lib;

  # Templates in ../palette, one output name each; a consumer imports its file from the palette directory.
  templates = {
    waybar = "waybar.css";
    mako = "mako";
    kitty = "kitty.conf";
    hyprlock = "hyprlock.conf";
    rofi = "rofi.rasi";
  };
  files = lib.attrValues templates;

  # The glass numbers (glass.nix) are filled in before matugen renders the colours.
  template =
    file:
    pkgs.writeText file (
      builtins.replaceStrings [ "@glass_alpha@" "@glass_border@" ] [ glass.alphaHex glass.borderHex ] (
        builtins.readFile (../palette + "/${file}")
      )
    );

  # @out@ is the render directory of the build script: a fixed path, so no wallpaper name is ever spliced into the file.
  matugenConfig = pkgs.writeText "matugen.toml" (
    ''
      [config]
      [config.custom_colors]
      red = "#ff5555"
      green = "#50fa7b"
      yellow = "#f1fa8c"
    ''
    + lib.concatStrings (
      lib.mapAttrsToList (name: file: ''
        [templates.${name}]
        input_path = "${template file}"
        output_path = "@out@/${file}"
      '') templates
    )
  );

  # --source-color-index picks the colour without asking on a terminal. A wallpaper whose render misses a file fails
  # the build: a consumer would otherwise start without its include.
  palettes = pkgs.runCommand "wallpaper-palettes" { nativeBuildInputs = [ pkgs.matugen ]; } ''
    export HOME=$TMPDIR
    render=$TMPDIR/render
    sed "s|@out@|$render|" ${matugenConfig} > $TMPDIR/matugen.toml
    mkdir -p $out
    ${common.findImages} -print0 > $TMPDIR/images
    while IFS= read -r -d "" img; do
      name=$(basename "$img")
      rm -rf "$render"
      mkdir "$render"
      matugen -q -c $TMPDIR/matugen.toml -m dark -t scheme-tonal-spot --source-color-index 0 image "$img"
      for f in ${lib.concatStringsSep " " files}; do
        [ -s "$render/$f" ] || { echo "matugen made no $f for $name" >&2; exit 1; }
      done
      mv "$render" "$out/$name"
    done < $TMPDIR/images
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
  inherit palettes files;

  # The palette that a fresh state directory starts with: the first wallpaper by name.
  defaultWallpaper =
    if images == [ ] then
      throw "assets/wallpapers has no .jpg, .jpeg or .png image"
    else
      lib.head images;
}
