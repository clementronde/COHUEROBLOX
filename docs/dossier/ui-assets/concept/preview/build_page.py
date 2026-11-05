"""Builds the 'Clic de brique' preview page: injects palette, data URIs and repeated markup."""
import base64
import io
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = sys.argv[1]
ICONS = os.path.join(REPO, "docs", "dossier", "ui-assets", "icons", "png")
BG = os.path.join(REPO, "docs", "dossier", "ui-assets", "concept", "run_landscape.png")
STUD = os.path.join(REPO, "docs", "dossier", "ui-assets", "stud_tile_128.png")

PAL = {"Ink": "1C1726", "Cream": "FFE8B8", "Tomato": "E63946", "Leaf": "3DBE4A", "Gold": "FFC21A",
       "Royal": "2D6BE6", "Sky": "3FD0F5", "Grape": "8C52E0", "Ember": "FF7A1A", "Bubblegum": "FF5FB0",
       "Stone": "9C9488", "Steel": "8EA6C2", "Bark": "6E4227", "Leather": "B5713A", "Plum": "4B3866", "Lime": "8FD13F"}
LIGHT, SHADOW = (0xFF, 0xF4, 0xD8), (0x2A, 0x1C, 0x3D)


def rgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def mix(a, b, t):
    return "#%02X%02X%02X" % tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


lines = []
for n, h in PAL.items():
    c = rgb(h)
    lines.append(f"--{n}:#{h};--{n}-l:{mix(c, LIGHT, .35)};--{n}-d:{mix(c, SHADOW, .35)};--{n}-dd:{mix(c, SHADOW, .6)};")
palette = "\n  ".join(lines)


def png_uri(path, size=None):
    im = Image.open(path).convert("RGBA")
    if size:
        im = im.resize((size, size), Image.LANCZOS)
    buf = io.BytesIO()
    im.save(buf, "PNG", optimize=True)
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()


def jpg_uri(path, width):
    im = Image.open(path).convert("RGB")
    w, h = im.size
    im = im.resize((width, round(h * width / w)), Image.LANCZOS)
    buf = io.BytesIO()
    im.save(buf, "JPEG", quality=80, optimize=True, progressive=True)
    return "data:image/jpeg;base64," + base64.b64encode(buf.getvalue()).decode()


def brick(style, inner="", cls="brick", extra=""):
    return f'<div class="{cls}" {extra} style="{style}">{inner}</div>'


def tvars(c):
    return f"--c:var(--{c});--cl:var(--{c}-l);--cd:var(--{c}-dd);"


hotbar = []
for k, (ic, lvl) in enumerate([("sword", "Lv4"), ("lightning", "Lv2"), ("firestaff", "Lv1"), (None, "")]):
    x = k * 54
    if ic:
        tag = brick(f"left:20px;top:32px;width:36px;height:22px;{tvars('Gold')}--lip:3px;--r:4px;border-width:2.5px",
                    '<div class="t" style="left:0;right:0;text-align:center;top:0;font-size:14px;--sw:4px;text-shadow:none">' + lvl + "</div>")
        hotbar.append(f'<div class="abs" style="left:{x}px;top:0;width:46px;height:46px;margin:-3px;box-sizing:content-box;background:var(--Cream);'
                      f'border:3px solid var(--Ink);border-radius:6px;box-shadow:inset 0 -4px 0 rgba(160,120,80,.45)">'
                      f'<div class="ico" style="left:4px;top:2px;width:38px;height:38px;background-image:url({{{{I_{ic}}}}})"></div>{tag}</div>')
    else:
        hotbar.append(f'<div class="abs" style="left:{x}px;top:0;width:46px;height:46px;margin:-3px;box-sizing:content-box;background:rgba(255,232,184,.3);'
                      f'border:3px dashed var(--Ink);border-radius:6px"></div>')

team = []
for k, (ini, nm, c, v) in enumerate([("A", "Alex", "Royal", .8), ("S", "Sam", "Grape", .45)]):
    y = k * 26
    team.append(brick(f"left:0;top:{y}px;width:24px;height:24px;{tvars(c)}--lip:3px;--r:4px;border-width:2.5px",
                      f'<div class="t" style="left:0;right:0;text-align:center;top:0;font-size:14px;--sw:4px;text-shadow:none">{ini}</div>'))
    team.append(f'<div class="t" style="left:30px;top:{y - 2}px;font-size:15px;--sw:4.4px">{nm}</div>')
    team.append(f'<div class="track" style="left:84px;top:{y + 7}px;width:74px;height:11px;border-width:2.5px;border-radius:3px">'
                f'<div class="abs" style="left:0;top:0;bottom:0;width:{round(v * 100)}%;background:var(--Leaf)"></div></div>')

dots = []
for x, y in [(20, 22), (60, 18), (70, 34), (26, 42), (66, 58), (18, 64), (54, 30)]:
    dots.append(f'<div class="abs" style="left:{x}px;top:{y}px;width:7px;height:7px;background:var(--Tomato);border:1.5px solid var(--Ink);border-radius:1px"></div>')
dots.append('<div class="abs" style="left:72px;top:6px;width:11px;height:11px;background:var(--Gold);border:2px solid var(--Ink)"></div>')
dots.append('<div class="abs" style="left:40px;top:70px;width:0;height:0;border-left:7px solid transparent;border-right:7px solid transparent;border-bottom:14px solid #fff;filter:drop-shadow(0 0 1px var(--Ink)) drop-shadow(0 0 1px var(--Ink))"></div>')

tiles = []
for tid, label, ic, c, x, y, s in [("tJump", "JUMP", "jump", "Royal", 716, 280, 84), ("tSlide", "SLIDE", "slide", "Royal", 638, 298, 66),
                                   ("tPing", "PING", "ping", "Royal", 742, 198, 58), ("tCapture", "CAPTURE", "capture_light", "Bubblegum", 638, 198, 66)]:
    fs = 17 if s >= 70 else 15
    tiles.append(
        f'<div class="abs tile" id="{tid}" tabindex="0" role="button" aria-label="{label.title()}" style="left:{x}px;top:{y}px;width:{s}px;height:{s + 10}px">'
        + brick(f"left:0;top:0;width:{s}px;height:{s}px;{tvars(c)}--lip:7px;--r:8px;--so:.35", cls="brick studs")
        + f'<div class="ico" style="left:{round(s * .15)}px;top:{round(s * .06)}px;width:{round(s * .7)}px;height:{round(s * .7)}px;background-image:url({{{{I_{ic}}}}})"></div>'
        + f'<div class="t" style="left:-10px;width:{s + 20}px;text-align:center;top:{s - 14}px;font-size:{fs}px;--sw:{round(fs * .3, 1)}px">{label}</div></div>')

recipes = [
    ("Fenêtre qui s'emboîte", "0,30 s puis 0,11 s", "Back Out, puis Quad Out", "Tombe de 34 px en passant de 86 % à 100 %, puis s'écrase de 4 % en touchant : c'est le « clic »."),
    ("Trophée qui saute", "0,38 s (départ +0,26 s)", "Quad Out", "Échelle 0 → 115 % → 100 %, rotation −40° → −8°."),
    ("Reflet sur les tenons", "0,56 s (+0,38 s)", "Quad Out", "Une bande claire traverse la barre de titre."),
    ("KO qui défilent", "0,70 s", "Cubic Out", "Le nombre compte de 0 au total, la tête de gobelin se dandine."),
    ("Tampon NEW BEST!", "0,22 s (+1,14 s)", "Back Out", "Arrive à 190 % penché de −16°, se plaque ; 12 tenons dorés jaillissent."),
    ("Cartes de choix", "0,28 s (+0,52 / +0,58 s)", "Back Out", "Montent de 22 px ; leur icône saute 0,1 s après."),
    ("Appui sur une brique", "0,06 s puis 0,18 s", "Quad Out, puis Back Out", "S'enfonce de 3 px (la hauteur de la lèvre), remonte avec 3 % de rebond. Son « clic »."),
    ("Choix d'une carte", "0,30 s", "Back Out", "Ton avatar tombe sur la carte, contour crème ; l'autre carte passe à 55 %."),
    ("Compte à rebours", "0,16 s par seconde", "Back Out", "Le chiffre retombe ; sous 5 s, la pastille pulse à 110 %."),
    ("+1 KO", "0,15 s", "Back Out", "Le compteur grossit à 116 %, la tête pivote. En rafale : une pulsation au plus toutes les 0,11 s."),
    ("Dégât", "0 s, puis 0,32 s (+0,22 s)", "Quad Out", "La barre tombe tout de suite, un reste crème fond derrière, la barre tremble de 4 px, le cœur se serre."),
    ("Soin", "0,30 s", "Quad Out", "La barre remonte, le cœur bat à 118 %."),
    ("Niveau gagné", "0,38 s", "Quad Out", "Le badge s'écrase puis rebondit, le nouveau chiffre tombe, 14 tenons bleus jaillissent, trois clics montants."),
    ("Capture prête", "0,26 s, puis 1,2 s en boucle", "Back Out, puis Linear", "La tuile monte en grandissant, un anneau rose pulse autour."),
]
rec_html = "".join(f"<tr><td>{a}</td><td class=\"num\">{b}</td><td><code>{c}</code></td><td>{d}</td></tr>" for a, b, c, d in recipes)

page = open(os.path.join(HERE, "template.html"), encoding="utf-8").read()
for key, val in [("{{HOTBAR}}", "".join(hotbar)), ("{{TEAM}}", "".join(team)), ("{{MAPDOTS}}", "".join(dots)),
                 ("{{TILES}}", "".join(tiles)), ("{{RECIPES}}", rec_html), ("{{PALETTE}}", palette)]:
    page = page.replace(key, val)
page = page.replace("{{BG}}", jpg_uri(BG, 1688)).replace("{{STUD}}", png_uri(STUD))
for f in os.listdir(ICONS):
    name = os.path.splitext(f)[0]
    key = "{{I_" + name + "}}"
    if key in page:
        page = page.replace(key, png_uri(os.path.join(ICONS, f), 128))
missing = sorted(set(p.split("}}")[0] for p in page.split("{{")[1:]))
out = os.path.join(HERE, "clic-de-brique.html")
open(out, "w", encoding="utf-8").write(page)
print("written", out, round(len(page) / 1024), "KB", "missing:", missing)
