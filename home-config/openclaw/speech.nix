{ lib, pkgs, ... }:

let
  piperTag = "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/ru/ru_RU";

  piperVoices = {
    "ru_RU-irina-medium.onnx" = {
      url = "${piperTag}/irina/medium/ru_RU-irina-medium.onnx";
      sha256 = "8ff38212d23da300bbe3705c645e6e5b9475f0bfde01558eb17813e22acaaaaa";
    };
    "ru_RU-irina-medium.onnx.json" = {
      url = "${piperTag}/irina/medium/ru_RU-irina-medium.onnx.json";
      sha256 = "c2ec28bb38e2b59e93b959b3e40348c1afebbd272f30fed5d41205d08e98a9d7";
    };
    "ru_RU-dmitri-medium.onnx" = {
      url = "${piperTag}/dmitri/medium/ru_RU-dmitri-medium.onnx";
      sha256 = "f073356ebc4bd0f80c5af58df2953a5988bd5bdab1eb38635ce960b071fbefcb";
    };
    "ru_RU-dmitri-medium.onnx.json" = {
      url = "${piperTag}/dmitri/medium/ru_RU-dmitri-medium.onnx.json";
      sha256 = "667ef3117bc642c2892dff7690d8bdc8ca4228aeaa783b2dc1416df632855e0d";
    };
    "ru_RU-denis-medium.onnx" = {
      url = "${piperTag}/denis/medium/ru_RU-denis-medium.onnx";
      sha256 = "15fab56e11a097858ee115545d0f697fc2a316c41a291a5362349fb870411b0a";
    };
    "ru_RU-denis-medium.onnx.json" = {
      url = "${piperTag}/denis/medium/ru_RU-denis-medium.onnx.json";
      sha256 = "831c860dac0b5073eaa81610a0a638ec23d90a6cf8e5f871b4485c2cec3767c8";
    };
    "ru_RU-ruslan-medium.onnx" = {
      url = "${piperTag}/ruslan/medium/ru_RU-ruslan-medium.onnx";
      sha256 = "72a5f88e0b20928064eb45d88e1daa21f8af62d18613580d32cbb4aed48dcf7f";
    };
    "ru_RU-ruslan-medium.onnx.json" = {
      url = "${piperTag}/ruslan/medium/ru_RU-ruslan-medium.onnx.json";
      sha256 = "706a4fb17bc304abd07809b552deae615e64dcbffbfbd09854ba37ca59e88117";
    };
  };

  # home.file entry. `target` MUST be relative to $HOME (home-manager rejects
  # absolute targets); the store basename follows the in-home filename.
  link = target: m: {
    inherit target;
    source = pkgs.fetchurl (m // { name = baseNameOf target; });
  };

  piperFiles = lib.mapAttrs' (
    name: m: lib.nameValuePair "piper-${name}" (link ".local/share/piper-voices/${name}" m)
  ) piperVoices;
in
{
  home = {
    packages = with pkgs; [
      piper-tts
      kokoro-ru
    ];

    file = piperFiles;
  };
}
