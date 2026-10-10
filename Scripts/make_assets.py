"""Builds Resources/Assets.xcassets from the Android art of Ivrit Together.

- AppIcon: 1024 x 1024 RGB PNG (no transparency) rendered with Pillow from the Android
  launcher art (app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml: background
  @color/brand_background #126F68 and foreground drawable/brand_mark.xml). The whole
  108 x 108 viewport is drawn, as in the Play Store icon (play-store/.../app-icon-512.png).
- Neighborhood: drawable-nodpi/neighborhood.png, copied unchanged.
- LaunchBackground and AccentColor: the app's Sand and Teal colours.

Usage: python Scripts/make_assets.py [path to the Android project]
The vector paths are read from the Android project when it is present; otherwise the
copy below (identical to brand_mark.xml) is used. The Android project is only read.
"""
import json
import re
import shutil
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "Resources" / "Assets.xcassets"
ANDROID = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT.parent / "IvritTogether"
RES = ANDROID / "app" / "src" / "main" / "res"

BACKGROUND = "#126F68"  # values/colors.xml brand_background
BRAND_MARK = [  # drawable/brand_mark.xml, viewport 108 x 108
    ("#126F68", "M0,0h108v108h-108z"),
    ("#F6C66E", "M25,28Q54,16 83,28L83,73Q54,61 25,73Z"),
    ("#FAF6EE", "M30,34Q41,29 51,34L51,68Q40,63 30,68Z M57,34Q68,29 78,34L78,68Q67,63 57,68Z"),
    ("#126F68", "M36,39L44,45L40,50L45,57L40,60L33,50L37,45L32,42Z M62,42L73,42L73,47L68,47L68,59L63,59L63,47L62,47Z"),
]
SAND = (0xFA, 0xF6, 0xEE)
TEAL = (0x12, 0x6F, 0x68)


def read_brand_mark():
    vector = RES / "drawable" / "brand_mark.xml"
    if not vector.exists():
        return BRAND_MARK, "embedded copy of drawable/brand_mark.xml"
    android = "{http://schemas.android.com/apk/res/android}"
    paths = [(p.get(android + "fillColor"), p.get(android + "pathData")) for p in ET.parse(vector).getroot()]
    return paths, str(vector)


def subpaths(data):
    """Polygons for the M/L/H/V/Q/Z commands used by the brand mark (absolute and relative)."""
    tokens = re.findall(r"[MmLlHhVvQqZz]|-?\d*\.?\d+(?:e-?\d+)?", data)
    shapes, current, x, y, start = [], [], 0.0, 0.0, (0.0, 0.0)
    command, index = None, 0

    def number():
        nonlocal index
        value = float(tokens[index])
        index += 1
        return value

    while index < len(tokens):
        if re.fullmatch(r"[A-Za-z]", tokens[index]):
            command = tokens[index]
            index += 1
            if command in "Zz":
                if current:
                    shapes.append(current)
                current, (x, y) = [], start
                continue
        relative = command.islower()
        kind = command.upper()
        if kind == "M":
            nx, ny = number(), number()
            x, y = (x + nx, y + ny) if relative else (nx, ny)
            if current:
                shapes.append(current)
            current, start = [(x, y)], (x, y)
            command = "l" if relative else "L"
        elif kind == "L":
            nx, ny = number(), number()
            x, y = (x + nx, y + ny) if relative else (nx, ny)
            current.append((x, y))
        elif kind == "H":
            n = number()
            x = x + n if relative else n
            current.append((x, y))
        elif kind == "V":
            n = number()
            y = y + n if relative else n
            current.append((x, y))
        elif kind == "Q":
            cx, cy, ex, ey = number(), number(), number(), number()
            if relative:
                cx, cy, ex, ey = x + cx, y + cy, x + ex, y + ey
            for step in range(1, 33):
                t = step / 32
                px = (1 - t) ** 2 * x + 2 * (1 - t) * t * cx + t * t * ex
                py = (1 - t) ** 2 * y + 2 * (1 - t) * t * cy + t * t * ey
                current.append((px, py))
            x, y = ex, ey
        else:
            raise ValueError("Unsupported path command " + command)
    if current:
        shapes.append(current)
    return shapes


def render_icon(paths, size=1024, supersample=4):
    canvas = size * supersample
    scale = canvas / 108.0
    image = Image.new("RGB", (canvas, canvas), BACKGROUND)
    draw = ImageDraw.Draw(image)
    for color, data in paths:
        for shape in subpaths(data):
            if len(shape) >= 3:
                draw.polygon([(px * scale, py * scale) for px, py in shape], fill=color)
    return image.resize((size, size), Image.LANCZOS).convert("RGB")


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def colour_set(name, rgb):
    write_json(ASSETS / f"{name}.colorset" / "Contents.json", {
        "colors": [{
            "color": {"color-space": "srgb", "components": {
                "alpha": "1.000",
                "red": "0x%02X" % rgb[0], "green": "0x%02X" % rgb[1], "blue": "0x%02X" % rgb[2]}},
            "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
    })


def main():
    write_json(ASSETS / "Contents.json", {"info": {"author": "xcode", "version": 1}})

    paths, source = read_brand_mark()
    icon_dir = ASSETS / "AppIcon.appiconset"
    icon_dir.mkdir(parents=True, exist_ok=True)
    icon = render_icon(paths)
    icon.save(icon_dir / "AppIcon-1024.png", optimize=True)
    write_json(icon_dir / "Contents.json", {
        "images": [{"filename": "AppIcon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
        "info": {"author": "xcode", "version": 1},
    })
    print("AppIcon rendered from", source)

    art = RES / "drawable-nodpi" / "neighborhood.png"
    target = ASSETS / "Neighborhood.imageset"
    target.mkdir(parents=True, exist_ok=True)
    if art.exists():
        shutil.copyfile(art, target / "neighborhood.png")
        print("Neighborhood copied from", art)
    elif not (target / "neighborhood.png").exists():
        raise SystemExit("neighborhood.png is missing; pass the Android project path")
    write_json(target / "Contents.json", {
        "images": [{"filename": "neighborhood.png", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
    })

    colour_set("LaunchBackground", SAND)
    colour_set("AccentColor", TEAL)
    print("Asset catalog written to", ASSETS)


if __name__ == "__main__":
    main()
