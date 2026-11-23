"""Checks the contrast of one rendered palette (one wallpaper, one mode): `contrast.py DIR LABEL`.

The Material text roles are harsher than a soft interface should be (14:1 to 16:1 for the text), and a mode can also
fall short, so each pair of colours the desktop draws must lie in a band: not below the floor of WCAG 2 (4.5:1 for text,
3:1 for graphics) and not above a soft ceiling. The values are read from the rendered files, so they include the
softening of style/. Prints every pair outside its band and exits with 1.
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


def read(path, pattern):
    with open(path) as f:
        return dict(re.findall(pattern, f.read(), re.M))


def main():
    directory, label = sys.argv[1:3]
    css = read(f"{directory}/waybar.css", r"@define-color (\w+) (#[0-9a-f]{6});")
    kitty = read(f"{directory}/kitty.conf", r"^(\w+) (#[0-9a-f]{6})")
    surface = css["surface"]

    # (name, foreground, background, lowest, highest)
    bands = [
        ("text", css["fg"], surface, 9, 21),
        ("secondary text", css["fg_dim"], surface, 5.5, 21),
        ("accent", css["accent"], surface, 4.5, 9),
        ("error", css["error"], surface, 3.5, 9.5),
        ("text on the accent container", css["on_accent_container"], css["accent_container"], 4.5, 21),
        ("prompt pill text (slot 16 on slot 17)", kitty["color16"], kitty["color17"], 4.5, 21),
        ("ANSI 8 and the suggestions", kitty["color8"], surface, 3, 9),
    ]
    names = {1: "red", 2: "green", 3: "yellow", 4: "blue", 5: "magenta", 6: "cyan"}
    bands += [(f"ANSI {n} ({name})", kitty[f"color{n}"], surface, 3.5, 9.5) for n, name in names.items()]

    failed = False
    for name, fg, bg, low, high in bands:
        ratio = contrast(fg, bg)
        if not low <= ratio <= high:
            failed = True
            print(f"{label}: {name} {fg} on {bg} is {ratio:.1f}:1, wanted {low} to {high}", file=sys.stderr)
    sys.exit(1 if failed else 0)


main()
