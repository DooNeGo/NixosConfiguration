{ pkgs ? import <nixpkgs> {} }:

let
  # Создаём SDK с userlocal-файлом
  dotnet = pkgs.dotnet-sdk_9.overrideAttrs (finalAttrs: previousAttrs: {
    postBuild = (previousAttrs.postBuild or "") + ''
      for sdkVersion in $out/sdk/*; do
        featureBand=$(basename "$sdkVersion")
        mkdir -p $out/metadata/workloads/$featureBand
        touch $out/metadata/workloads/$featureBand/userlocal
      done
    '';
  });

  # FHS-окружение для MAUI
  mauiFhsEnv = pkgs.buildFHSEnv {
    name = "maui-fhs";
    targetPackages = with pkgs; [
      dotnet
      jetbrains.rider
    ];
  };
in
pkgs.mkShell {
  packages = with pkgs; [
    jdk17
    mauiFhsEnv
  ];

  DOTNET_ROOT = "${dotnet}/share/dotnet";
  PATH="${dotnet}/bin:$PATH";
}
