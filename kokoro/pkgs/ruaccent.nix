# W1 (plan step 3 / research P2): ruaccent 1.5.8.3 — universal PyPI wheel with
# the accentuator data tree symlinked INSIDE the installed package, because
# RUAccent.load() defaults workdir to dirname(__file__) and then reads
# dictionary/ nn/ koziev/ from there (research P2; the old module achieved
# this by mutating site-packages by hand — we use a standard postInstall hook
# instead, plan P2).
#
# Wiring (kokoro/flake.nix):
#   ruaccent = pkgs.callPackage ./pkgs/ruaccent.nix { inherit data; };
# Arguments:
#   * `data`       — REQUIRED callPackage argument: the pkgs/data.nix (W2)
#                    output set; this file consumes data.ruaccent-data, whose
#                    roots are exactly dictionary/ nn/ koziev/ (+ README.md) —
#                    verified against acc-lfs.nix and the pinned prefetch tree
#                    /nix/store/7spca8svp…-source. W4 can re-wire it as e.g.
#                    { data = pkgs.callPackage ./pkgs/data.nix { }; }.
#   * `pycrfsuite` — OPTIONAL override with a default that builds this flake's
#                    own ./pycrfsuite.nix (python3Packages scope), so the
#                    current flake.nix line `{ inherit data; }` already
#                    evaluates; W4 may instead pass
#                    pycrfsuite = packages.pycrfsuite — same derivation either
#                    way, one cached output.
#   * python deps are read from python3Packages explicitly (they are not
#     top-level nixpkgs attributes under their python names).
#
# Python pin (plan step 0 precheck, verified 2026-10-03): nixpkgs pin
# c59305bab → python 3.14.7 (same as the home-config/openclaw flake). The
# wheel is universal (py2.py3-none-any), so it follows whatever interpreter
# the pin provides — no cp-tag assert needed here (unlike pycrfsuite.nix).
# The site-packages path comes from python3Packages.python.sitePackages
# (== pkgs.python3.sitePackages of the same instance); the old module's
# hardcoded "lib/python3.14/site-packages" constant is deliberately not
# repeated (plan §1.2).
#
# Licenses — VERIFIED 2026-10-03 (W1 duty, plan risk 2: the old module's
# "Apache-2.0" claim is WRONG/unverified — three sources conflict):
#   1. PyPI 1.5.8.3 wheel AND sdist (both uploaded 2024-10-23):
#      dist-info/LICENSE = CC BY-NC-ND 4.0 (Attribution-NonCommercial-
#      NoDerivatives) — the file embedded in the artifact we ship.
#   2. PyPI METADATA classifier: "License :: OSI Approved :: Apache Software
#      License" — never matched (1); treat as stale/wrong metadata.
#   3. GitHub Den4ikAI/ruaccent LICENSE: commit 2026-07-17 on that path —
#      "Change license from Creative Commons to MIT. For v1 ruaccent" — the
#      copyright holder relicensed the v1 line (= 1.5.8.x, including our
#      version) to MIT after (1); repo LICENSE today = MIT (Copyright 2026
#      Denis Petrov). README's "commercial use — contact me" predates (3).
# Decision: meta.license = mit — current copyright statement (3) governs the
# v1 code line, and it keeps the package free (no allowUnfree in the kokoro
# flake, matching the plan's assumption of a free package).
# ⚠ The wheel we install still embeds the stale CC BY-NC-ND text in
# dist-info/LICENSE. If the coordinator prefers the conservative reading of
# the shipped artifact, flip to lib.licenses."cc-by-nc-nd-40" (free=false →
# the flake then needs allowUnfree) — one-line change, flagged in the W1
# report as an open question.
# NOT covered by this meta: the accentuator DATA collection symlinked below
# (dictionary/nn/koziev — koziev/rupostagger, rulemma, ONNX models, ~680 MiB,
# mixed provenance). Its licensing stays an open question (plan risk 2) —
# verify against the HF ruaccent/accentuator model card during W2/W5. Local
# personal use only either way.
{ lib
, data
  # data.nix (W2) output set; data.ruaccent-data is linked into the package
, fetchPypi
, python3Packages
  # provides buildPythonPackage, python deps and the pinned interpreter
, autoPatchelfHook
  # not resolvable inside the python package set (verified 2026-10-03); passed
  # through to the pycrfsuite default below (pkgs.callPackage resolves it)
, pycrfsuite ? python3Packages.callPackage ./pycrfsuite.nix {
    # Explicit overrides — without them callPackage inside the python set
    # resolves `python3Packages` to the deliberate throw alias
    # (python-aliases.nix:60) and fails on missing autoPatchelfHook (both
    # verified 2026-10-03, first build attempt: "error: do not use
    # python3Packages when building Python packages …"). W4 may override
    # this whole argument with packages.pycrfsuite instead.
    inherit python3Packages autoPatchelfHook;
  }
  # default = this flake's own wheel package (see header); override supported
}:

python3Packages.buildPythonPackage rec {
  pname = "ruaccent";
  version = "1.5.8.3";

  # Universal wheel; `pyproject` must stay unset (mk-python-derivation asserts
  # pyproject/format are mutually exclusive at this nixpkgs rev).
  format = "wheel";

  src = fetchPypi {
    inherit pname version;
    format = "wheel";
    # ruaccent-1.5.8.3-py2.py3-none-any.whl — fetchPypi's default dist/
    # python/abi/platform tags already match this universal wheel exactly
    # (legacy URL verified HTTP 200 on 2026-10-03). hash re-verified the same
    # day: sha256 of the fresh download = 35c220a0…b05b1 = the old module's
    # line 171 value (SRI below).
    hash = "sha256-NcIgoHqpw8EVdKa+frWk2+TF9gvljK+4DpxtB5brBbE=";
  };

  # Full upstream Requires-Dist: huggingface_hub onnxruntime transformers
  # sentencepiece numpy python-crfsuite razdel (exactly the 7 METADATA
  # entries). format="wheel" enables python-runtime-deps-check-hook, which
  # FAILS the build if any declared distribution is absent from the build
  # env — so this list is load-bearing, not decorative. Import chain checked
  # against the wheel sources: ruaccent/__init__ → ruaccent.py imports
  # huggingface_hub; omograph/accent/stress/yo models import numpy +
  # onnxruntime + transformers; text_preprocessor imports razdel;
  # python-crfsuite resolves to our pycrfsuite derivation (dist-info name
  # python-crfsuite; importlib.metadata normalizes [-_.]).
  dependencies = [
    python3Packages."huggingface-hub"
    python3Packages.numpy
    python3Packages.onnxruntime
    pycrfsuite
    python3Packages.razdel
    python3Packages.sentencepiece
    python3Packages.transformers
  ];

  # Data INSIDE the package (plan P2): symlink the W2 store tree next to the
  # module code. The wheel ships no data dirs of its own (verified: 15
  # entries, only ruaccent/*.py + dist-info), so no clobbering is possible;
  # read-only store targets are fine because we link *to* them, while the
  # package dir itself is writable during installPhase (no chmod hacks —
  # the old module's chmod -R u+w dance disappears with site-packages
  # mutation, plan §1.2).
  postInstall = ''
    pkg="$out/${python3Packages.python.sitePackages}/ruaccent"
    test -d "$pkg" || { echo "ruaccent: package dir $pkg missing after install" >&2; exit 1; }
    ln -s "${data.ruaccent-data}/dictionary" "$pkg/dictionary"
    ln -s "${data.ruaccent-data}/nn"         "$pkg/nn"
    ln -s "${data.ruaccent-data}/koziev"     "$pkg/koziev"
  '';

  # Import only — no RUAccent() instantiation, so no data loading and no
  # network during the check (RUAccent.__init__/load() are only called
  # explicitly). Data content is exercised at runtime by W5 smoke:
  #   nix shell … -c python -c 'import ruaccent; print(ruaccent.__file__)'
  pythonImportsCheck = [ "ruaccent" ];

  meta = {
    description = "Russian accentizer (rule + NN) with offline accentuator dictionaries";
    homepage = "https://github.com/Den4ikAI/ruaccent";
    # MIT per the 2026-07-17 CC→MIT relicense of the v1 line; PyPI metadata
    # (Apache classifier, CC BY-NC-ND LICENSE file) is stale — full evidence
    # and the flip-to-unfree alternative in the header.
    license = lib.licenses.mit;
  };
}