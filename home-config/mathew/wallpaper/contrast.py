"""Checks the contrast of one rendered palette (one wallpaper, one mode): `contrast.py DIR LABEL`.

Each pair of colours the desktop draws must reach its floor: 7:1 for the main text, 4.5:1 for the other text and
accents (WCAG 2 AA), 3:1 for graphics. There are no ceilings: the softness comes from the matugen contrast
(style/). The colours are read from waybar.css, which holds every colour of the palette under its matugen name.
Prints every pair below its floor and exits with 1; with `--table` prints every ratio instead.
"""
import re
import sys


def luminance(hexcolor):
    def channel(v):
        v /= 255
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4

    r, g, b = (int(hexcolor[i : i + 2], 16) for i in (1, 3, 5))
    return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)


def contrast(a, b):
    hi, lo = sorted((luminance(a), luminance(b)), reverse=True)
    return (hi + 0.05) / (lo + 0.05)


# (foreground, background, floor)
PAIRS = [
    ("on_surface", "surface", 7),
    ("on_surface", "surface_container_highest", 4.5),
    ("on_surface_variant", "surface", 4.5),
    ("primary", "surface", 4.5),
    ("error", "surface", 4.5),
    ("green", "surface", 4.5),
    ("yellow", "surface", 4.5),
    ("on_error_container", "error_container", 4.5),
    ("on_secondary_container", "secondary_container", 4.5),
    ("outline", "surface", 3),
]


def main():
    table = "--table" in sys.argv
    directory, label = [a for a in sys.argv[1:] if a != "--table"][:2]
    with open(f"{directory}/waybar.css") as f:
        colors = dict(re.findall(r"@define-color (\w+) (#[0-9a-f]{6});", f.read()))

    failed = False
    for fg, bg, floor in PAIRS:
        ratio = contrast(colors[fg], colors[bg])
        if table:
            print(f"{label} {fg}/{bg} {ratio:.2f}")
        if ratio < floor:
            failed = True
            print(f"{label}: {fg} {colors[fg]} on {bg} {colors[bg]} is {ratio:.1f}:1, wanted at least {floor}", file=sys.stderr)
    sys.exit(1 if failed else 0)


main()
