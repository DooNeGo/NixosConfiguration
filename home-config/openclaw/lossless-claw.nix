# lossless-claw plugin (vendored npm tarballs).
#
# @martian-engineering/lossless-claw has no Nix source, and its single
# runtime dep (@sinclair/typebox@0.34.48) is not resolvable by nix-openclaw's
# install.mjs (tarball ships no node_modules/lockfile). So we fetch both npm
# tarballs by pinned sha256 (registry URLs are deterministic per
# name@version) and lay the plugin out manually:
#   $out/                     package.json + openclaw.plugin.json + dist/
#   $out/node_modules/@sinclair/typebox/
# Pinned sha256 in installPhase fails the build if fetched bytes differ:
#   lossless-claw-1.1.1.tgz  d03408d496e9be13a2e296530a0cd0cbe0d3b2ba7acafdef617bb16ffbb2c6d8
#   typebox-0.34.48.tgz      f35ed4b7228f9feab2acb79459cd86fc9e77522b585edeeccfd6a1702856be04
# (fetchurl's own sha256 check enforces the same pins at download time.
# fetchurl works identically on macOS/nix-darwin — no repo-local files.)
#
# nix-openclaw README: raw plugins.load.paths must NOT be mixed with
# runtimePlugins/runtimePluginSources in the same instance, so searxng is
# also served via load.paths (pkgs.openclawRuntimePlugins.searxng, built
# from the pinned runtime lock by the nix-openclaw overlay in flake.nix).

{
  pkgs,
  version ? "1.1.1",
  lcmSha256 ? "d03408d496e9be13a2e296530a0cd0cbe0d3b2ba7acafdef617bb16ffbb2c6d8",
  typeboxSha256 ? "f35ed4b7228f9feab2acb79459cd86fc9e77522b585edeeccfd6a1702856be04",
}:

let
  losslessTgz = pkgs.fetchurl {
    url = "https://registry.npmjs.org/@martian-engineering/lossless-claw/-/lossless-claw-${version}.tgz";
    sha256 = lcmSha256;
  };
  typeboxTgz = pkgs.fetchurl {
    url = "https://registry.npmjs.org/@sinclair/typebox/-/typebox-0.34.48.tgz";
    sha256 = typeboxSha256;
  };
in
pkgs.stdenvNoCC.mkDerivation {
  pname = "lossless-claw";
  inherit version;
  srcs = [
    losslessTgz
    typeboxTgz
  ];
  dontBuild = true;
  installPhase = ''
    runHook preInstall
    test "$(sha256sum ${losslessTgz} | cut -d' ' -f1)" = "${lcmSha256}"
    test "$(sha256sum ${typeboxTgz} | cut -d' ' -f1)" = "${typeboxSha256}"
    mkdir -p $out
    tar -xzf ${losslessTgz} --strip-components=1 -C $out
    mkdir -p $out/node_modules/@sinclair/typebox
    tar -xzf ${typeboxTgz} --strip-components=1 -C $out/node_modules/@sinclair/typebox
    runHook postInstall
  '';
}
