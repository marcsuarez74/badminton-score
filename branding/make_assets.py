#!/usr/bin/env python3
"""Génère les assets graphiques RacketStream (icône launcher, bannière store, visuel marketing).

Palette (identité produit — phase 4c) :
  court-nuit #04180A · volée #2FE05C · clair-ligne #EAFFF3 · filet #0D2B1E · live #FF5A3C
"""
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import math, os

COURT = (0x04, 0x18, 0x0A)      # court-nuit
VOLEE = (0x2F, 0xE0, 0x5C)      # volée (vert sync)
CLAIR = (0xEA, 0xFF, 0xF3)      # clair-ligne
FILET = (0x0D, 0x2B, 0x1E)      # filet
LIVE = (0xFF, 0x5A, 0x3C)       # live (pastille)
GRIS = (0x5A, 0x6A, 0x60)       # ombre-court
GRISL = (0x8F, 0xA8, 0x9B)      # clair atténué

OUT = os.path.dirname(os.path.abspath(__file__))
os.makedirs(OUT, exist_ok=True)

F_BLACK = os.path.join(os.path.dirname(__file__), "fonts", "ArchivoBlack.ttf")
F_VAR = os.path.join(os.path.dirname(__file__), "fonts", "ArchivoVar.ttf")


def font_black(px):
    return ImageFont.truetype(F_BLACK, px)


def font_var(px, weight=400):
    f = ImageFont.truetype(F_VAR, px)
    try:
        f.set_variation_by_axes([100, weight])  # [wdth, wght]
    except Exception:
        try:
            f.set_variation_by_name("Regular" if weight <= 400 else "Bold")
        except Exception:
            pass
    return f


# ---------------------------------------------------------------- icône 60x60
def icon(size=60, ss=8):
    """L'arc de sync (270°) avec son extrémité lumineuse — le geste signature."""
    S = size * ss
    img = Image.new("RGBA", (S, S), COURT + (255,))
    d = ImageDraw.Draw(img)
    cx = cy = S // 2
    r = int(S * 0.36)
    w = max(int(S * 0.11), 6)
    # l'arc : ouverture en haut à droite (comme le liseré qui se dessine)
    d.arc([cx - r, cy - r, cx + r, cy + r], start=100, end=400, fill=VOLEE, width=w)
    # l'extrémité lumineuse au bout de l'arc (angle 400°)
    a = math.radians(400)
    px_, py_ = cx + r * math.cos(a), cy + r * math.sin(a)
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    dg = ImageDraw.Draw(glow)
    gr = int(S * 0.09)
    dg.ellipse([px_ - gr, py_ - gr, px_ + gr, py_ + gr], fill=VOLEE + (255,))
    glow = glow.filter(ImageFilter.GaussianBlur(S * 0.02))
    img = Image.alpha_composite(img, glow)
    d = ImageDraw.Draw(img)
    br = int(S * 0.055)
    d.ellipse([px_ - br, py_ - br, px_ + br, py_ + br], fill=CLAIR)
    return img.resize((size, size), Image.LANCZOS).convert("RGB")


# ------------------------------------------------------- bannière store 720x405
def banner(w=720, h=405, ss=2):
    S = ss
    img = Image.new("RGB", (w * S, h * S), COURT)
    d = ImageDraw.Draw(img)

    # --- le court en perspective (structure graphique, au trait)
    # trapèze du court vu depuis un coin : lignes fines, très discrètes
    def line(p1, p2, color, width):
        d.line([p1[0] * S, p1[1] * S, p2[0] * S, p2[1] * S], fill=color, width=width)

    deep = (0x11, 0x2E, 0x20)
    faint = (0x0C, 0x21, 0x16)
    # ligne de fond de court + couloirs, en perspective fuyante vers la droite
    line((430, 40), (690, 60), deep, 2)
    line((410, 150), (720, 150), faint, 2)
    line((390, 260), (720, 260), faint, 2)
    line((370, 385), (720, 385), faint, 2)
    line((430, 40), (370, 385), deep, 2)   # ligne latérale fuyante
    line((560, 49), (640, 385), faint, 2)  # ligne centrale de service
    # le filet : trait vertical, un poil plus présent
    line((500, 20), (455, 405), (0x1A, 0x4A, 0x30), 3)

    # --- le wordmark
    f_wm = font_black(int(64 * S))
    d.text((56 * S, 128 * S), "RacketStream", font=f_wm, fill=CLAIR)

    # la tagline + les sports
    f_tag = font_var(int(23 * S), 500)
    d.text((58 * S, 218 * S), "Le score de ton match, en direct sur ton stream", font=f_tag, fill=GRISL)
    f_sp = font_var(int(18 * S), 400)
    d.text((58 * S, 258 * S), "badminton, padel, tennis, squash", font=f_sp, fill=GRIS)

    # --- le bandeau de score (droite, façon retransmission TV)
    bx, by, bw, bh = int(360 * S), int(292 * S), int(320 * S), int(84 * S)
    rad = int(14 * S)
    d.rounded_rectangle([bx, by, bx + bw, by + bh], radius=rad, fill=FILET, outline=(0x1A, 0x4A, 0x30), width=2 * S)
    f_name = font_var(int(17 * S), 600)
    d.text((bx + 22 * S, by + 12 * S), "MARC", font=f_name, fill=CLAIR)
    d.text((bx + bw - 92 * S, by + 12 * S), "PAUL", font=f_name, fill=GRISL)
    f_score = font_black(int(44 * S))
    d.text((bx + 20 * S, by + 32 * S), "21", font=f_score, fill=VOLEE)
    d.text((bx + 96 * S, by + 40 * S), "-", font=f_score, fill=GRIS)
    d.text((bx + 130 * S, by + 32 * S), "18", font=f_score, fill=CLAIR)

    # --- la pastille LIVE (le seul contre-accent : le produit diffuse)
    lx, ly, lr = bx + bw - 26 * S, by - 6 * S, int(9 * S)
    d.ellipse([lx - lr - 3 * S, ly - lr - 3 * S, lx + lr + 3 * S, ly + lr + 3 * S], fill=(0x20, 0x0A, 0x06))
    d.ellipse([lx - lr, ly - lr, lx + lr, ly + lr], fill=LIVE)

    return img.resize((w, h), Image.LANCZOS)


# ------------------------------------------------- visuel marketing 1080x1080
def marketing(size=1080, ss=2):
    S = ss
    img = Image.new("RGB", (size * S, size * S), COURT)
    d = ImageDraw.Draw(img)
    c = size * S // 2

    # vignettage discret (profondeur photographique, pas un wash)
    vig = Image.new("L", (size * S, size * S), 0)
    dv = ImageDraw.Draw(vig)
    dv.ellipse([-size * S * 0.2, -size * S * 0.2, size * S * 1.2, size * S * 1.2], fill=26)
    vig = vig.filter(ImageFilter.GaussianBlur(size * S * 0.12))
    img = Image.composite(Image.new("RGB", img.size, (0x01, 0x05, 0x03)), img, vig)
    d = ImageDraw.Draw(img)

    # --- la montre ronde
    R = int(size * 0.40 * S)
    # bezel : deux anneaux sombres
    d.ellipse([c - R - 14 * S, c - R - 14 * S, c + R + 14 * S, c + R + 14 * S], fill=(0x0D, 0x10, 0x12))
    d.ellipse([c - R, c - R, c + R, c + R], fill=COURT)

    # --- l'écran SCORE (reproduction de l'essence de l'écran de la montre)
    # le liseré de sync : arc sur le bord de l'écran
    lr = R - int(10 * S)
    d.arc([c - lr, c - lr, c + lr, c + lr], start=100, end=400, fill=VOLEE, width=int(7 * S))

    # les noms
    f_n = font_var(int(52 * S), 600)
    d.text((c, c - int(0.44 * R)), "MARC", font=f_n, fill=CLAIR, anchor="mm")
    d.text((c, c + int(0.30 * R)), "PAUL", font=f_n, fill=GRISL, anchor="mm")

    # le score
    f_s = font_black(int(140 * S))
    d.text((c - int(0.275 * R), c - int(0.02 * R)), "21", font=f_s, fill=CLAIR, anchor="mm")
    d.text((c + int(0.275 * R), c - int(0.02 * R)), "18", font=f_s, fill=GRISL, anchor="mm")
    d.text((c, c - int(0.03 * R)), "-", font=font_black(int(110 * S)), fill=GRIS, anchor="mm")

    # les pips de sets (2-1)
    pip_r = int(11 * S)
    gap = int(30 * S)
    y = c + int(0.16 * R)
    for i in range(2):  # MARC 2 sets
        x = c - int(0.11 * R) + i * gap
        d.ellipse([x - pip_r, y - pip_r, x + pip_r, y + pip_r], fill=VOLEE)
    for i in range(1):  # PAUL 1 set
        x = c + int(0.06 * R) + i * gap
        d.ellipse([x - pip_r, y - pip_r, x + pip_r, y + pip_r], outline=GRISL, width=int(3 * S))

    return img.resize((size, size), Image.LANCZOS)


if __name__ == "__main__":
    icon(60).save(os.path.join(OUT, "launcher_icon.png"))
    icon(120).save(os.path.join(OUT, "launcher_icon@2x.png"))
    banner().save(os.path.join(OUT, "store-banner-720x405.png"))
    marketing().save(os.path.join(OUT, "app-marketing-1080.png"))
    print("assets générés dans", OUT)
