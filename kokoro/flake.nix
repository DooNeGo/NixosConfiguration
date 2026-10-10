{
  description = "kokoro-ru standalone flake: Russian Kokoro TTS packages + pinned data trees";

  inputs = {
    # Pin: nixpkgs revision verified during plan research (kokoro, razdel,
    # onnxruntime, soundfile, cffi, torch, misaki present; ruaccent and
    # pycrfsuite are packaged by this flake itself).
    nixpkgs.url = "github:nixos/nixpkgs/c59305bab2065cfecc4944690d9eedbb56f3a9fa";
  };

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      # Data trees: 2 fetchTree (pinned rev + narHash) + 35 per-file LFS
      # fetchurl (sha256 == LFS oid), assembled into two store trees.
      # Returns { kokoro-ru-data, ruaccent-data }.
      data = pkgs.callPackage ./pkgs/data.nix { };
    in
    {
      packages.${system} = {
        kokoro-ru-data = data.kokoro-ru-data;
        ruaccent-data = data.ruaccent-data;

        pycrfsuite = pkgs.callPackage ./pkgs/pycrfsuite.nix { };
        ruaccent = pkgs.callPackage ./pkgs/ruaccent.nix { inherit data; };
        kokoro-ru = pkgs.callPackage ./pkgs/kokoro-ru.nix { inherit data; };
      };
    };
}
