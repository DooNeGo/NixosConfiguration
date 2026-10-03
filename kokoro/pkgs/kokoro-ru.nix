# kokoro-ru — «связующий» python-пакет (план P4) + CLI (P5) для русского
# TTS Kokoro-RU. Часть standalone flake kokoro/; НЕ дублирует fetcher'ы:
# модели/голоса/espeak/конфиги приходят ТОЛЬКО из data (дерево W2),
# ruaccent — аргументом/дефолтом (пакет W1), pycrfsuite пропагируется
# последним внутри ruaccent.
#
# Wiring (фактический, см. flake.nix — чужой файл, сюда не входит):
#   pkgs.callPackage ./pkgs/kokoro-ru.nix { inherit data; }
# scope — верхний (pkgs), поэтому python-механика читается из
# python3Packages явно (тот же приём, что в pycrfsuite.nix/ruaccent.nix);
# `ruaccent` имеет default, идентичный строке flake'а
# `pkgs.callPackage ./pkgs/ruaccent.nix { inherit data; }` — один drv,
# один кеш.
#
# PYTHONPATH для bin/kokoro-ru-say собирает штатный wrap-python-hook из
# propagatedBuildInputs (grep .kokoro-wrapped старого модуля исчезает как
# класс); KOKORO_RU_DATA кладётся туда же через makeWrapperArgs —
# штатный механизм nixpkgs, не вложенный wrapProgram. Каталог site-packages
# берётся у интерпретатора (python.sitePackages) — хардкода
# lib/python3.X/site-packages нет.
{ lib
, python3Packages
, fetchPypi
, autoPatchelfHook
, data
, ruaccent ? python3Packages.callPackage ./ruaccent.nix {
    # Все non-defaulted аргументы ruaccent.nix — ЯВНО: callPackage внутри
    # python-сета резолвит его аргумент python3Packages в deliberate-throw
    # (python-aliases.nix:60), а autoPatchelfHook в python-сетe
    # отсутствует (оба факта проверены при первом же eval). lib/data/
    # fetchPypi/autoPatchelfHook/python3Packages здесь по значению
    # совпадают с `pkgs.callPackage ./pkgs/ruaccent.nix { inherit data; }`
    # из flake.nix → один и тот же drv, один кеш.
    inherit lib data fetchPypi python3Packages autoPatchelfHook;
  }
}:

assert lib.assertMsg (data ? kokoro-ru-data)
  "kokoro-ru: аргумент data без kokoro-ru-data — ожидается выход pkgs/data.nix (W2)";

let
  python = python3Packages.python;
  inherit (python3Packages) kokoro razdel onnxruntime soundfile cffi;
  kokoroRuData = data.kokoro-ru-data;
in
python3Packages.buildPythonApplication {
  pname = "kokoro-ru";
  version = "1.0.0";

  # Нет pyproject/src: кода пакета нет как такового — installPhase ставит
  # CLI-скрипт и ru_g2p.py, окружение даёт wrap-hook.
  format = "other";
  dontUnpack = true;
  dontBuild = true;

  # Композиция фиксирована контрактом плана §2.2: pycrfsuite и данные
  # ruaccent пропагируются самим ruaccent.
  propagatedBuildInputs = [
    kokoro
    razdel
    ruaccent
    onnxruntime
    soundfile
    cffi
  ];

  # makeWrapperArgs дописывается wrap-python-hook'ом в ЕДИНСТВЕННУЮ обёртку
  # $out/bin/*: PYTHONPATH из propagated + KOKORO_RU_DATA (GC-root дерева
  # данных). Гонка вложенных wrapProgram (свой postFixup поверх
  # wrapPythonPrograms) не нужна.
  makeWrapperArgs = [ "--set" "KOKORO_RU_DATA" "${kokoroRuData}" ];

  # Импорт-чек одним процессом, порядок важен: сначала kokoro (выставляет
  # EspeakWrapper через misaki), затем ru_g2p (внутри RuG2P.__init__
  # полагается на это), затем ruaccent. ru_g2p импортирует ruaccent/phonemizer
  # только лениво внутри __init__, сам модуль — json/re/pathlib.
  pythonImportsCheck = [ "kokoro" "ru_g2p" "ruaccent" ];

  installPhase = ''
    runHook preInstall

    # CLI — отдельный python-скрипт (не heredoc): wrap-python-hook сам
    # перепишет shebang на интерпретатор и добавит PYTHONPATH.
    install -Dm755 ${../cli/kokoro_cli.py} $out/bin/kokoro-ru-say

    # ru_g2p.py — модуль НАШЕГО пакета (install, а не мутация чужого
    # site-packages); путь — python.sitePackages у интерпретатора.
    install -Dm644 ${kokoroRuData}/ru_g2p.py \
      "$out"/${python.sitePackages}/ru_g2p.py

    runHook postInstall
  '';

  meta = {
    description = "Русский Kokoro-TTS: связующий пакет + CLI kokoro-ru-say";
    homepage = "https://huggingface.co/zaakirio/kokoro-ru";
    # Наш wrapper + kokoro (hexgrad, asl20) + ru_g2p (zaakirio — производная
    # Apache-2.0 Kokoro по model card HF). Веса/данные espeak лицензируются
    # отдельно — см. kokoro-ru-data (W2).
    license = lib.licenses.asl20;
    mainProgram = "kokoro-ru-say";
    platforms = lib.platforms.linux;
  };
}