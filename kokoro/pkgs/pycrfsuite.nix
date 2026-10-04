# W1 (plan step 2 / research P3): python-crfsuite 0.9.12 — prebuilt cp314
# manylinux wheel from PyPI (the only available binary for Python 3.14; no
# `crfsuite` C library exists in nixpkgs, so there is no source build path —
# research P3).
#
# Wiring (kokoro/flake.nix):
#   pycrfsuite = pkgs.callPackage ./pkgs/pycrfsuite.nix { };
# All three arguments auto-resolve from nixpkgs top-level at pin c59305bab
# (fetchPypi exists there — verified 2026-10-03; buildPythonPackage does NOT,
# hence the python3Packages argument). Call via pkgs.callPackage as above; a
# direct python3Packages.callPackage would resolve python3Packages to the
# deliberate `throw` alias inside the python set (python-aliases.nix:60) and
# lacks autoPatchelfHook — if W4 ever switches scope it must pass
# { inherit python3Packages autoPatchelfHook; } explicitly (ruaccent.nix's
# default argument already does exactly this).
# Flake output/plan attribute name: `pycrfsuite` (plan §2.2); derivation pname
# is the PyPI distribution name below.
#
# Python pin (plan step 0 precheck, verified 2026-10-03): this flake's nixpkgs
# pin c59305bab provides python 3.14.7 — identical to the home-config/openclaw
# flake (also 3.14.7). The cp314 wheel tag matches both. The assert below
# fails loudly if the pin moves to another Python minor; then regenerate
# dist/python/abi/platform tags + hash (PyPI ships wheels per cp-version), or
# switch to a source build — do NOT keep the stale wheel (research P3).
# The interpreter is taken from python3Packages.python (== pkgs.python3 of the
# same nixpkgs instance), so no bare `python3` argument is required.
#
# Licenses — VERIFIED 2026-10-03 from the shipped wheel and upstream repos
# (W1 duty, plan risk 2; plan P3's "BSD заявлен в PyPI, уточнить" was wrong
# for the wrapper — PyPI now says MIT):
#   * python-crfsuite wrapper: MIT — wheel dist-info/licenses/LICENSE.txt =
#     "MIT License, Copyright (c) 2014-2017 ScrapingHub Inc. and contributors";
#     PyPI METADATA "License: MIT License" + OSI MIT classifier; GitHub
#     scrapinghub/python-crfsuite LICENSE.txt = same MIT text.
#   * vendored C backend CRFsuite (git submodule chokkan/crfsuite, statically
#     linked into _pycrfsuite.cpython-314-x86_64-linux-gnu.so): BSD-3-Clause —
#     COPYING verified: "The BSD license. Copyright (c) 2007-2010 Naoaki
#     Okazaki" with all three clauses.
#   * vendored liblbfgs (submodule chokkan/liblbfgs, statically linked):
#     MIT — COPYING verified (Copyright 1990 Jorge Nocedal, 2007-2010 Naoaki
#     Okazaki).
#   meta.license = [ mit bsd3 ] covers wrapper + vendored CRFsuite (+ MIT
#   liblbfgs); all free — no allowUnfree needed for this package.
{
  lib,
  fetchPypi,
  python3Packages,
  # provides buildPythonPackage and the pinned interpreter (.python, .sitePackages)
  autoPatchelfHook,
  stdenv,
  # manylinux wheel fix: the prebuilt _pycrfsuite.so needs libstdc++ but ships
  # without RPATH (verified 2026-10-03: build failed at pythonImportsCheck with
  # "ImportError: libstdc++.so.6: cannot open shared object file"). autoPatchelf
  # rewrites the .so's RPATH to the nixpkgs gcc runtime below, which then also
  # enters the output closure — import works in the check and at runtime.
}:

assert lib.assertMsg
  (
    lib.versionAtLeast python3Packages.python.version "3.14"
    && lib.versionOlder python3Packages.python.version "3.15"
  )
  "pycrfsuite 0.9.12 is cp314-locked (python ${python3Packages.python.version}); regenerate dist/python/abi/platform tags + hash for the new interpreter (plan step 0)";

python3Packages.buildPythonPackage rec {
  pname = "python-crfsuite";
  version = "0.9.12";

  # ELF patching of the wheel's prebuilt extension module (header).
  nativeBuildInputs = [ autoPatchelfHook ];
  # libstdc++/libgcc_s for the manylinux .so — nixpkgs-built, RPATH-patched by
  # autoPatchelfHook in fixup (runs before pythonImportsCheck).
  buildInputs = [ stdenv.cc.cc.lib ];

  # wheel-only package. `pyproject` must stay unset: mk-python-derivation
  # asserts pyproject and format are mutually exclusive at this nixpkgs rev.
  format = "wheel";

  src = fetchPypi {
    # fetchPypi interpolates pname verbatim into path and filename, while
    # wheel files use underscore name normalization (PEP 503) — hence
    # python_crfsuite here instead of the derivation pname above.
    pname = "python_crfsuite";
    inherit version;
    format = "wheel";
    # ABI/platform tags of the only cp314 binary wheel (x86_64 Linux):
    #   python_crfsuite-0.9.12-cp314-cp314-manylinux_2_24_x86_64.manylinux_2_28_x86_64.whl
    dist = "cp314";
    python = "cp314";
    abi = "cp314";
    platform = "manylinux_2_24_x86_64.manylinux_2_28_x86_64";
    # Legacy fetchPypi URL verified HTTP 200 → canonical hash path on
    # 2026-10-03. sha256 a2fe0e67…138eb1 (hex from the old module line 178)
    # re-verified against the PyPI API digest and a fresh download. If PyPI
    # ever drops the legacy path the FOD fails loudly (hash-mismatch/404, no
    # silent drift) — swap in the canonical files.pythonhosted.org URL, which
    # is worth keeping pinned here:
    #   https://files.pythonhosted.org/packages/3b/72/eea7c742783c9aa15e9505b0361c9e40c4e3ba86ba7976179a590a8b1ab6/python_crfsuite-0.9.12-cp314-cp314-manylinux_2_24_x86_64.manylinux_2_28_x86_64.whl
    hash = "sha256-ov4OZ2A2XXKI5jZhxKs8ERCuDLHDb7u+0j5eiJwTjrE=";
  };

  # No runtime deps: the wheel's only Requires-Dist entries are dev extras
  # (tox/black/…), which python-runtime-deps-check-hook skips via marker eval.

  # Import the compiled .so at build time (plan step 2 acceptance: `python -c
  # 'import pycrfsuite'`) — fails on ABI/interpreter drift instead of at first
  # use.
  pythonImportsCheck = [ "pycrfsuite" ];

  meta = {
    description = "Python binding for CRFsuite (conditional random fields); ruaccent dependency";
    homepage = "https://chokkan.gitlab.io/pycrfsuite/";
    # MIT wrapper + BSD-3 CRFsuite (+ MIT liblbfgs) — full evidence in header.
    license = [
      lib.licenses.mit
      lib.licenses.bsd3
    ];
    # The wheel is cp314 + manylinux x86_64 only.
    platforms = [ "x86_64-linux" ];
  };
}
