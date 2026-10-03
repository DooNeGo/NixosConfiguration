{
  description = "kokoro-ru standalone flake: Russian Kokoro TTS packages + pinned data trees (W2 skeleton; integration is wired by W4)";

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

        # Contract for W1/W3 package files: they may take
        #   data = { kokoro-ru-data; ruaccent-data; }
        # via the `data` argument passed below.
        # Until ./pkgs/{pycrfsuite,ruaccent,kokoro-ru}.nix land (W1/W3),
        # `nix flake check` reports these three as missing files — expected
        # during W2; the two data outputs above evaluate on their own.
        pycrfsuite = pkgs.callPackage ./pkgs/pycrfsuite.nix { };
        ruaccent = pkgs.callPackage ./pkgs/ruaccent.nix { inherit data; };
        kokoro-ru = pkgs.callPackage ./pkgs/kokoro-ru.nix { inherit data; };
      };
    };
}
