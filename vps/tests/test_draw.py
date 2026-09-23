"""Tests du dessin du scorebug (renderer VPS) — design phase 5 en Pillow.

Le renderer produit des frames RGBA 1280x720. Aucun match → frame totalement
transparente. Un match → le scorebug semi-transparent (alpha ≈ 0,66) posé
selon --position, avec les couleurs des camps (#2FE05C / #E5484D).
"""

import pytest
from PIL import Image

from renderer import draw_frame, compute_bug_layout


STATE = {
    "score_me": 5, "score_opp": 3,
    "sets_me": 1, "sets_opp": 0,
    "current_set": 1, "sets_to_win": 2,
}
STATE_BOTH_SETS = {**STATE, "sets_me": 1, "sets_opp": 1}

TEAM1 = (47, 224, 92)    # #2FE05C
TEAM2 = (229, 72, 77)    # #E5484D

NAMES = ("MARC", "PAUL")


def count_near(img, rgb, tol=25):
    """Nombre de pixels dont RGB est proche de rgb (alpha > 0)."""
    n = 0
    r0, g0, b0 = rgb
    for px in img.getdata():
        r, g, b, a = px
        if a > 0 and abs(r - r0) <= tol and abs(g - g0) <= tol and abs(b - b0) <= tol:
            n += 1
    return n


def bug_crop(img):
    x, y, w, h = compute_bug_layout(STATE, NAMES, "topright")
    return img.crop((x, y, x + w, y + h))


def test_frame_vide_totalement_transparente():
    img = draw_frame(None)
    assert img.size == (1280, 720)
    assert img.mode == "RGBA"
    assert img.getextrema()[3] == (0, 0)


def test_layout_tient_dans_la_frame_avec_marge():
    x, y, w, h = compute_bug_layout(STATE, NAMES, "topright")
    assert y == 16                       # marge haute 16 px (aligné ffmpeg)
    assert x + w == 1280 - 16            # marge droite 16 px
    assert 300 < w < 720
    assert 50 < h < 120


def test_positions_autorisees():
    _, _, w, _ = compute_bug_layout(STATE, NAMES, "topleft")
    assert compute_bug_layout(STATE, NAMES, "topleft")[0] == 16
    assert compute_bug_layout(STATE, NAMES, "topright")[0] == 1280 - 16 - w
    assert compute_bug_layout(STATE, NAMES, "topcenter")[0] == (1280 - w) // 2


def test_position_invalide_leve_erreur():
    with pytest.raises(ValueError):
        compute_bug_layout(STATE, NAMES, "bottomleft")


def test_fond_semi_transparent_dans_le_bug():
    img = draw_frame(STATE, names=NAMES, position="topright")
    x, y, w, h = compute_bug_layout(STATE, NAMES, "topright")
    px = img.getpixel((x + 10, y + h - 10))   # un coin du fond, sans texte
    assert px[0] <= 30 and px[1] <= 30 and px[2] <= 30
    assert 150 <= px[3] <= 185                # alpha ≈ 0,66


def test_transparent_hors_bug():
    img = draw_frame(STATE, names=NAMES, position="topright")
    assert img.getpixel((2, 359))[3] == 0     # bord gauche, hors bug
    assert img.getpixel((640, 700))[3] == 0   # bas centre, hors bug


def test_scores_etchamps_en_blanc_pur():
    crop = bug_crop(draw_frame(STATE, names=NAMES))
    r, g, b, a = crop.getextrema()
    assert r[1] == 255 and g[1] == 255 and b[1] == 255   # du blanc pur (texte)
    assert a[1] == 255


def test_pip_gagne_couleur_camp_1():
    crop = bug_crop(draw_frame(STATE, names=NAMES))
    assert count_near(crop, TEAM1) > 30          # 8x8 px - coins arrondis


def test_pip_gagne_couleur_camp_2():
    crop = bug_crop(draw_frame(STATE_BOTH_SETS, names=NAMES))
    assert count_near(crop, TEAM2) > 30


def test_pips_non_gagnes_ont_juste_le_contour():
    # state : sets_opp = 0 → aucun pixel plein de TEAM2 dans le bug
    crop = bug_crop(draw_frame(STATE, names=NAMES))
    assert count_near(crop, TEAM2) == 0


def test_pips_nombre_total_suit_sets_to_win():
    # 3 sets à gagner → 6 pips → plus de surface de contour que 2+2
    state3 = {**STATE, "sets_to_win": 3}
    crop2 = bug_crop(draw_frame(STATE, names=NAMES))
    crop3 = bug_crop(draw_frame(state3, names=NAMES))
    # le pip border = blanc alpha ~0,35 ; on compare via la présence d'alpha moyen
    alphas2 = crop2.getchannel("A").histogram()
    alphas3 = crop3.getchannel("A").histogram()
    mid2 = sum(alphas2[70:110])
    mid3 = sum(alphas3[70:110])
    assert mid3 > mid2


def test_chiffres_tabulaires_meme_largeur():
    # font-variant-numeric: tabular-nums → pour un même nb de chiffres,
    # la largeur est identique (les chiffres ne « sautent » pas au tick).
    w5 = compute_bug_layout(STATE, NAMES, "topright")[2]
    w8 = compute_bug_layout({**STATE, "score_me": 8}, NAMES, "topright")[2]
    w19 = compute_bug_layout({**STATE, "score_me": 19, "score_opp": 18}, NAMES, "topright")[2]
    w95 = compute_bug_layout({**STATE, "score_me": 95, "score_opp": 18}, NAMES, "topright")[2]
    assert w5 == w8
    assert w19 == w95
    assert w19 > w5          # deux chiffres occupent plus qu'un seul (min-width 46)
