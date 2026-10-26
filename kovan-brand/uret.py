"""KOVAN marka varlıklarını tek SVG kaynağından üretir.

Chrome headless SVG'yi şeffaf zeminde çizer, Pillow boyutlandırır ve
ICO/ICNS paketlerini oluşturur. Çalıştırma: python3 kovan-brand/uret.py
"""
import os
import shutil
import subprocess
import tempfile

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "kovan-brand", "cikti")
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
INK = "#141414"
PAPER = "#ffffff"

# Pointy-top hexagon cell, stroke drawn with round joins (viewBox 0 0 100 100).
def hexagon(color, stroke=13):
    return (f'<polygon points="50,10 84.6,30 84.6,70 50,90 15.4,70 15.4,30" '
            f'fill="none" stroke="{color}" stroke-width="{stroke}" stroke-linejoin="round"/>')


def mark_svg(color, stroke=13):
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">{hexagon(color, stroke)}</svg>'


def app_icon_svg(inset, radius, mark_scale):
    """Dark tile with a white cell; inset/radius in a 1024 canvas."""
    size = 1024 - 2 * inset
    m = size * mark_scale
    off = (1024 - m) / 2
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">'
            f'<rect x="{inset}" y="{inset}" width="{size}" height="{size}" rx="{radius}" fill="{INK}"/>'
            f'<svg x="{off}" y="{off}" width="{m}" height="{m}" viewBox="0 0 100 100">{hexagon(PAPER)}</svg>'
            f'</svg>')


def lockup_html(color):
    # Mark first, then the wordmark; mark ≈ 1.9× cap height, centred on it.
    return f"""<!doctype html><html><head><meta charset="utf-8">
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@800&display=swap" rel="stylesheet">
<style>html,body{{margin:0;background:transparent}}
.l{{display:flex;align-items:center;gap:30px;height:180px;padding:0 6px;width:max-content}}
.l svg{{width:132px;height:132px}}
.w{{font:800 104px/1 Inter,sans-serif;letter-spacing:.04em;color:{color}}}</style></head>
<body><div class="l">{mark_svg(color)}<div class="w">KOVAN</div></div></body></html>"""


def render(markup, w, h, path, html=False):
    with tempfile.TemporaryDirectory() as d:
        src = os.path.join(d, "a.html")
        body = markup if html else (
            '<!doctype html><html><head><style>html,body{margin:0;background:transparent}'
            f'svg{{display:block;width:{w}px;height:{h}px}}</style></head><body>{markup}</body></html>')
        with open(src, "w") as f:
            f.write(body)
        subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                        "--default-background-color=00000000", f"--window-size={w},{h}",
                        "--virtual-time-budget=4000", f"--screenshot={path}", f"file://{src}"],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def trim(path):
    img = Image.open(path).convert("RGBA")
    img.crop(img.getbbox()).save(path)


def resized(src, size):
    return Image.open(src).convert("RGBA").resize((size, size), Image.LANCZOS)


def main():
    os.makedirs(OUT, exist_ok=True)
    o = lambda n: os.path.join(OUT, n)

    # Masters: macOS tile follows Apple's grid (824 tile, 100 inset); others are full-bleed.
    render(app_icon_svg(100, 185, 0.56), 1024, 1024, o("mac-icon.png"))
    render(app_icon_svg(0, 230, 0.56), 1024, 1024, o("icon.png"))
    # Menu bar template: black cell, heavier stroke so it survives 16–22 pt.
    render(mark_svg("#000000", 15), 512, 512, o("tray-master.png"))
    render(lockup_html(INK), 1100, 180, o("logo_light.png"), html=True)
    render(lockup_html(PAPER), 1100, 180, o("logo_dark.png"), html=True)
    for n in ("logo_light.png", "logo_dark.png"):
        trim(o(n))

    for s in (32, 64, 128, 256):
        resized(o("icon.png"), s).save(o(f"{s}x{s}.png"))
    resized(o("tray-master.png"), 60).save(o("mac-tray-dark-x2.png"))
    resized(o("tray-master.png"), 48).save(o("mac-tray-light-x2.png"))

    ico_sizes = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
    Image.open(o("icon.png")).save(o("icon.ico"), sizes=ico_sizes)
    Image.open(o("icon.png")).save(o("tray-icon.ico"), sizes=[(16, 16), (24, 24), (32, 32), (48, 48)])

    iconset = o("AppIcon.iconset")
    os.makedirs(iconset, exist_ok=True)
    for base in (16, 32, 128, 256, 512):
        resized(o("mac-icon.png"), base).save(os.path.join(iconset, f"icon_{base}x{base}.png"))
        resized(o("mac-icon.png"), base * 2).save(os.path.join(iconset, f"icon_{base}x{base}@2x.png"))
    subprocess.run(["iconutil", "-c", "icns", iconset, "-o", o("AppIcon.icns")], check=True)
    shutil.rmtree(iconset)

    with open(o("icon.svg"), "w") as f:
        f.write(app_icon_svg(0, 230, 0.56))
    with open(o("mark.svg"), "w") as f:
        f.write(mark_svg(INK))
    print("tamam:", sorted(os.listdir(OUT)))


if __name__ == "__main__":
    main()
