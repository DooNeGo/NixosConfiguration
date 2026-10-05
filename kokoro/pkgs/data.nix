# W2 — data trees for kokoro-ru / ruaccent (plan P1).
#
# Mechanical transformation of the ready-made manifests:
#   /tmp/kokoro-test/kr-lfs.nix         (21 files, zaakirio/kokoro-ru @ d649c57b)
#   /tmp/kokoro-test/acc-lfs.nix        (14 files, ruaccent/accentuator @ b78ae5ea)
#   /tmp/kokoro-test/prefetch-*.json    (rev + narHash for both repos)
# into:
#   2 builtins.fetchTree  — pinned rev + narHash, whole git tree minus LFS
#     content (nix 2.34 cannot smudge git-lfs: the LFS batch endpoint 404s,
#     so LFS blobs arrive as pointer files);
#   35 per-file fetchurl  — pinned resolve/<rev>/<rel>?download=true URLs with
#     sha256 == LFS oid (the LFS oid is the sha256 of the actual content);
#   2 runCommand assemblies — copy the tree, swap the 35 pointer files for
#     the fixed-output downloads.
#
# Expected sizes (lfs-sizes.json): kr 662 119 684 B, acc 713 396 199 B.
# Returns { kokoro-ru-data, ruaccent-data }.

{
  lib,
  fetchurl,
  runCommand,
}:

let
  # ---- pinned git trees (narHash from prefetch-{kokoro,acc}.json) ----
  krRev = "d649c57b239b18c4c384378127cbf01dba039bc1";
  accRev = "b78ae5ea1e62beaf138bed1865cd8c3b0b5ca855";

  kokoroTree = builtins.fetchTree {
    type = "git";
    url = "https://huggingface.co/zaakirio/kokoro-ru";
    rev = krRev;
    narHash = "sha256-MJKhTp9Q/fjoSWv/GCpgvkM8STjwg/C/BxpFHojYbpk=";
  };

  accTree = builtins.fetchTree {
    type = "git";
    url = "https://huggingface.co/ruaccent/accentuator";
    rev = accRev;
    narHash = "sha256-jBgpmbZ7hArhmFwIVsBEFMA46CYr+KXhDQQTgMzxMyw=";
  };

  # ---- LFS manifests: rel -> sha256 (= LFS oid), verbatim from kr-lfs.nix ----
  krLfs = {
    "espeak-data/af_dict" = "25729d3bf4c4a0f08da60aea9eb5a0cf352630f83fab1ab0c3955b7740da1776";
    "espeak-data/ar_dict" = "72316426e797777fe4df9420935a3b6a79b37d7e3f3948537ba71cd7b21b2541";
    "espeak-data/ca_dict" = "59f0f94d03cb6341a1b952ff735d8f0d0cb10136a593462558db7cfc8ee5318d";
    "espeak-data/cmn_dict" = "2a41ddab7213d0284a984def6b40c72cbc40b346d3220db08c6ae324f46d59aa";
    "espeak-data/da_dict" = "ae6c2dd4f0f4d38342918a776a9e2c46d919572f02336c864f843ff7b262caf8";
    "espeak-data/en_dict" = "1053f74a34af38abb6fbd64b7838dacbc655a687c48ce1bb663d364a127b05de";
    "espeak-data/fa_dict" = "e3aa6e751a344da7924b0ed871e06a6afb053f6bfe87dfd7914ffa24e90cd03c";
    "espeak-data/hu_dict" = "f9e3a5174ce89c48caf93865bdce2a7d92fa3da09d4147668020542edbe87b87";
    "espeak-data/ia_dict" = "1c665603a82beb81e0cef2878c9b44642ae6d519e301fbbd06326e03325febf3";
    "espeak-data/it_dict" = "7ce5b6b4e2ee251516708584267a413a3c02b2fa07cb527a2eb421fbbb3b12cf";
    "espeak-data/lb_dict" = "d819a062b9722334f187540d3530fac1de365cd200d4a466f5ecccd7e3c05772";
    "espeak-data/phondata" = "a0b643b155cb6b12628d9e7865b57d9fca0d35844614f2594a5e009c80c80bb4";
    "espeak-data/ru_dict" = "fec9c58731c7670b31ec6c36045d954760308234057c449565878b7e17266433";
    "espeak-data/ta_dict" = "8f3d855c8d7a35ad0e2b22bc7c15a8830e5fc235492894e5db40458655076ecd";
    "espeak-data/ur_dict" = "74b60e4331f532810ccfc70751ad07ab440647550a2d25823f44663a0dfa86fb";
    "espeak-data/yue_dict" = "1d26afa203034698772107abfff1b53acbee30434700a4d2b75dee98951588f8";
    "kokoro-ru-v2-base.pth" = "3bbee5bc05cfa182afc365b9116eaed8355f939c3c0af8aa0e43fdc45343ca15";
    "kokoro-ru-v2-dima.pth" = "658ae47e24224257ea9f83c88ea7743c5c9f0922c6bc339805ffebcfdbcb2b24";
    "voices/dima.pt" = "80d4d216b5906c232ede48f2c07ab3aee0785e34d1df6ec6dc8cf44767d74c69";
    "voices/masha.pt" = "464d64ae793647c3b3f9d1f08ce5b11c641a61799f0bca65f111e6aad5d0a362";
    "voices/sveta.pt" = "248c00e98f7ce20c31ff5537b52ea3d3b204a58845d86da73960f30f112f60a7";
  };

  # ---- LFS manifests: rel -> sha256 (= LFS oid), verbatim from acc-lfs.nix ----
  accLfs = {
    "dictionary/accents.json.gz" = "aa460ebba90de00fbbf3d41d121961f605b98667e45efb7920f127473b15515e";
    "dictionary/accents_nn.json.gz" =
      "8395664000b80c1afe09bfea3650945b0933482b8e3dee5bb9d429eb18c44935";
    "dictionary/omographs.json.gz" = "04a9e81c68d65f65ba493fe0110f99e79087548c2beeec3032e2b66e28706f36";
    "dictionary/yo_homographs.json.gz" =
      "c4ee777bbbab87f9eac838f370ad92974e079d02b21903e480c54b5f0c8c60d1";
    "dictionary/yo_words.json.gz" = "a19fa89a964a0691d9fe4ee384783e3934904891843d8f59a1c480d67947a82a";
    "koziev/rulemma/rulemma.dat" = "bf2b3ef3ff7a0aa6e4250aa4e9c8ed568e25f825deebdb12dee1b46b785ba9fc";
    "koziev/rupostagger/database/ruword2tags.db" =
      "a06848e656bef642aafb4440c03554fa78f2f32dde92ea66f3f86ce9977b167e";
    "koziev/rupostagger/rupostagger.model" =
      "21b7b0bfd7427b5fdc1604052176db8aa3b139b3ce03be440cfce48536f8e5ef";
    "koziev/rupostagger/ruword2tags.dat" =
      "dde47b5f1d48ff899887ac07812dcabd2966e48e84646f3065bfd06627c2af58";
    "nn/nn_accent/big.onnx" = "47e69d9ae19f2a82e21b1c70f6a4bbfb1abc5759e98b2e67d009c5e9d7af18c9";
    "nn/nn_accent/model.onnx" = "4e393144e45626f6f1062a0784ef06f921b97321a8e7b87ac2a09a892286500a";
    "nn/nn_omograph/turbo3.1/model.onnx" =
      "2cb6a174c4cdb45bd3132b4f7c8a3779fc4b6869863180ed7d0e421bcd453dbd";
    "nn/nn_stress_usage_predictor/model.onnx" =
      "3d547500637b4ddfec8880ed6d1405fd50ee9d3f0131ef8a2a69dcf961dbefeb";
    "nn/nn_yo_homograph_resolver/model.onnx" =
      "42cc85bf0c4b319dfe3d89fa17b162a92fd5e1c651a657cb3d5f44978d4e70ac";
  };

  # One pinned LFS blob; sha256 == LFS oid (content hash).
  lfsFetch =
    repo: rev: rel: sha256:
    fetchurl {
      # flattened relative path keeps store names unique and readable
      # (the acc tree has four files called model.onnx)
      name = builtins.replaceStrings [ "/" ] [ "-" ] rel;
      url = "https://huggingface.co/${repo}/resolve/${rev}/${rel}?download=true";
      inherit sha256;
    };

  # Copy a pinned tree into $out and replace its LFS pointer files with the
  # fixed-output downloads.
  mkTree =
    {
      name,
      tree,
      repo,
      rev,
      lfs,
    }:
    runCommand name
      {
        preferLocalBuild = true;
      }
      ''
        mkdir -p "$out"
        cp -a ${tree}/. "$out"/
        # store files/dirs are read-only; the copy must be writable so the
        # pointer files can be swapped out
        chmod -R u+w "$out"
        ${lib.concatStrings (
          lib.mapAttrsToList (rel: sha256: ''
            rm -f "$out/${rel}"
            mkdir -p "$out/$(dirname ${rel})"
            cp ${lfsFetch repo rev rel sha256} "$out/${rel}"
          '') lfs
        )}
      '';

in
{
  kokoro-ru-data = mkTree {
    name = "kokoro-ru-data";
    tree = kokoroTree;
    repo = "zaakirio/kokoro-ru";
    rev = krRev;
    lfs = krLfs;
  };

  ruaccent-data = mkTree {
    name = "ruaccent-data";
    tree = accTree;
    repo = "ruaccent/accentuator";
    rev = accRev;
    lfs = accLfs;
  };
}
