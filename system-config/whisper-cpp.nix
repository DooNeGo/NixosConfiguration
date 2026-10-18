{ lib, pkgs, ... }:

let
  hf = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main";

  whisperModels = {
    small = {
      url = "${hf}/ggml-small.bin";
      sha256 = "1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b";
    };
    medium = {
      url = "${hf}/ggml-medium.bin";
      sha256 = "6c14d5adee5f86394037b4e4e8b59f1673b6cee10e3cf0b11bbdbee79c156208";
    };
  };

  modelDir = "/var/lib/whisper-cpp";

  modelStores = lib.mapAttrs (
    name: m: pkgs.fetchurl (m // { name = "ggml-${name}.bin"; })
  ) whisperModels;
in
{
  environment.systemPackages = with pkgs; [
    whisper-cpp
    ffmpeg-headless
  ];

  systemd.tmpfiles.rules = [
    "d ${modelDir} 0755 root root -"
  ]
  ++ lib.mapAttrsToList (name: store: "L+ ${modelDir}/ggml-${name}.bin - - - - ${store}") modelStores;
}
