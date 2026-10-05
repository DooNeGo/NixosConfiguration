#!/usr/bin/env python3
# kokoro-ru-say — оффлайн-синтез русской речи Kokoro-RU (CPU-only), wav.
#
# Замена heredoc-CLI старого kokoro.nix (план P5): отдельный python-скрипт,
# никакого grep-PYTHONPATH и /var/lib — каталог данных приходит через
# env KOKORO_RU_DATA (обёртка makeWrapper в kokoro-ru.nix) или флаг -d.
#
# Синтез — через KPipeline (а не raw KModel-выражение старого CLI):
#   * KPipeline даёт чанкинг по предложениям (~400 симв.), контракт
#     infer/скорости и загрузку голосов;
#   * G2P подменяется на RuG2P с ЯВНЫМИ путями данных
#     (RuG2P(espeak_data=…, vocab_path=…)) — симлинков в site-packages нет;
#   * ru_g2p.py лежит в site-packages СВОЕГО пакета (installPhase в
#     kokoro-ru.nix), не мутацией чужого.
#
# ВАЖНО: wrap-python-hook (nixpkgs wrap-python.nix) вставляет preamble
# site.addsitedir ПЕРЕД первой рабочей строкой скрипта, поэтому модульный
# docstring здесь не используется (перестал бы быть __doc__), а первый
# рабочий блок — обычные импорты stdlib.
#
# Флаги совместимы со старым CLI: -v sveta|masha|dima, -r rate,
# -c checkpoint, -o out.wav ('-' = wav в stdout), -d data_dir.
# Коды выхода: 2 — аргументы/пустой текст, 3 — нет данных, 4 — нет аудио.
import argparse
import contextlib
import io
import os
import sys

VOICES = ("sveta", "masha", "dima")
SAMPLE_RATE = 24000  # kokoro-ru: 24 kHz mono PCM16, как старый CLI
CHUNK_GAP_SEC = 0.15  # пауза между чанками KPipeline (не портит интонацию)


def die(code, msg):
    print(f"kokoro-ru-say: {msg}", file=sys.stderr)
    raise SystemExit(code)


def parse_args(argv=None):
    ap = argparse.ArgumentParser(
        prog="kokoro-ru-say",
        description="Kokoro-RU: оффлайн-синтез русской речи (CPU, wav).",
    )
    ap.add_argument("-v", "--voice", default="sveta", choices=list(VOICES),
                    help="голос (по умолчанию sveta; у dima свой checkpoint)")
    ap.add_argument("-r", "--rate", type=float, default=1.0,
                    help="скорость речи, >1 быстрее (по умолчанию 1.0)")
    ap.add_argument("-c", "--checkpoint", default=None, metavar="PATH",
                    help="переопределить checkpoint модели (.pth)")
    ap.add_argument("-o", "--out", default="-", metavar="PATH",
                    help="выходной wav; '-' — wav в stdout (по умолчанию)")
    ap.add_argument("-d", "--data-dir", metavar="DIR",
                    default=os.environ.get("KOKORO_RU_DATA"),
                    help="каталог данных (по умолчанию env KOKORO_RU_DATA)")
    ap.add_argument("text", nargs="*",
                    help="текст для синтеза; если не задан — читается stdin")
    return ap.parse_args(argv)


def find(data_dir, candidates, what):
    """Первый существующий кандидат из data_dir; иначе exit 3 с перечнем."""
    for rel in candidates:
        p = os.path.join(data_dir, rel)
        if os.path.exists(p):
            return p
    die(3, f"{what}: не найдено в {data_dir} "
           f"(проверенные пути: {', '.join(candidates)}; "
           "дерево данных W2 подключено?)")
    raise AssertionError("unreachable")


class OovLog:
    """Обёртка RuG2P: печатает IPA/OOV в stderr (паритет со старым CLI).

    KPipeline вызывает g2p(chunk) и отбрасывает OOV — здесь диагностика
    возвращается, не меняя контракт (стр, множество) -> (стр, множество).
    """

    def __init__(self, inner):
        self._inner = inner

    def __call__(self, text):
        ipa, oov = self._inner(text)
        print(f"IPA: {ipa}", file=sys.stderr)
        if oov:
            print(f"OOV symbols (kept as-is): {sorted(oov)}", file=sys.stderr)
        return ipa, oov


def main(argv=None) -> int:
    a = parse_args(argv)

    # --- Текст: аргументы, иначе stdin -----------------------------------
    if a.text:
        text = " ".join(a.text)
    elif not sys.stdin.isatty():
        text = sys.stdin.read()
    else:
        die(2, "TEXT required (или передайте текст stdin)")
    if not text.strip():
        die(2, "пустой текст (ни аргументов, ни stdin)")
    if a.rate <= 0:
        die(2, f"-r/--rate должен быть > 0 (получено {a.rate})")

    # --- Пути данных (дерево W2) — проверяем ДО тяжёлых импортов --------
    if not a.data_dir:
        die(3, "каталог данных не задан: нужен -d или env KOKORO_RU_DATA")
    if not os.path.isdir(a.data_dir):
        die(3, f"каталог данных не существует: {a.data_dir}")
    data = a.data_dir
    # острые ru_dict — обязательное условие RuG2P (иначе стрессы игнорируются
    # и русский стресс хуже baseline; см. ru_g2p.RuG2P.__init__)
    if not os.path.exists(os.path.join(data, "espeak-data", "ru_dict")):
        die(3, f"espeak-data/ru_dict не найден в {data} (дерево W2 не собрано?)")
    vocab_path = find(data, ("kokoro-config.json",),
                      "kokoro-config.json (vocab RuG2P)")
    model_cfg = find(data, ("config.json",),
                     "config.json (конфиг KModel, офлайн без hf-ходов)")
    if a.checkpoint:
        if not os.path.exists(a.checkpoint):
            die(3, f"checkpoint из -c не найден: {a.checkpoint}")
        ckpt = a.checkpoint
    else:
        # sveta/masha делят base-checkpoint, dima — свой (старый CLI)
        base = "dima" if a.voice == "dima" else "base"
        ckpt = find(data, (f"kokoro-ru-v2-{base}.pth",), f"checkpoint {base}")
    # в старом /var/lib-layout голоса лежали плоско (voices-sveta.pt) —
    # принимаем оба布局а
    voicepack = find(data, (f"voices/{a.voice}.pt", f"voices-{a.voice}.pt"),
                     f"голосовой пак {a.voice}")

    # --- Тяжёлые импорты: порядок важен ----------------------------------
    # Сначала kokoro: `from misaki import espeak` на его пути выставляет
    # EspeakWrapper library+data (в nixpkgs — патчем на store-пути), на что
    # полагается RuG2P.__init__ («sets loader lib+data paths»).
    import numpy as np
    import soundfile as sf
    import torch
    from kokoro import KModel, KPipeline
    from ru_g2p import RuG2P

    # --- Синтез -----------------------------------------------------------
    # redirect_stdout: любые сторонние print'ы не должны портить wav в '-o -'.
    with contextlib.redirect_stdout(sys.stderr):
        # CPU-only: KModel грузит веса map_location='cpu' и не переводится
        # на cuda; KPipeline получает готовую модель → без device-авто-детекта.
        # repo_id и config — явно: иначе KModel/KPipeline печатают WARNING
        # в stdout и пытаются ходить в hf_hub.
        model = KModel(repo_id="zaakirio/kokoro-ru",
                       config=model_cfg, model=ckpt).eval()
        # lang_code='e': в LANG_CODES upstream KPipeline русского ('r') нет;
        # нужна только не-английская ветка (предложение-чанкинг + вызов
        # self.g2p(chunk)), а сам g2p подменяется на RuG2P ниже.
        pipe = KPipeline(lang_code="e", repo_id="zaakirio/kokoro-ru",
                         model=model)
        pipe.g2p = OovLog(RuG2P(espeak_data=os.path.join(data, "espeak-data"),
                                vocab_path=vocab_path))
        pieces = []
        with torch.no_grad():
            for res in pipe(text, voice=voicepack, speed=a.rate):
                if res.audio is not None:
                    pieces.append(np.atleast_1d(res.audio.cpu().numpy()))
    if not pieces:
        die(4, "синтез не дал аудио (пустой результат G2P?)")

    # склейка чанков KPipeline с короткой паузой
    gap = np.zeros(int(SAMPLE_RATE * CHUNK_GAP_SEC), dtype=pieces[0].dtype)
    parts = []
    for i, p in enumerate(pieces):
        if i:
            parts.append(gap)
        parts.append(p)
    arr = np.concatenate(parts)

    buf = io.BytesIO()
    sf.write(buf, arr, SAMPLE_RATE, format="WAV", subtype="PCM_16")
    wav = buf.getvalue()
    if a.out == "-":
        sys.stdout.buffer.write(wav)
        sys.stdout.buffer.flush()
    else:
        with open(a.out, "wb") as f:
            f.write(wav)
        print(f"wrote {a.out} ({len(wav)} bytes, {arr.size} samples)",
              file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
